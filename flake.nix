{
  description = "dox-populi: a Screeps client specified in Paradox, soup to nuts via nix";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*";

    paradox.url = "gitlab:paradox_labs/paradox";

    typed-screeps = {
      url = "github:screepers/typed-screeps";
      flake = false;
    };

    secrix.url = "github:Platonic-Systems/secrix";

    disko = {
      url = "https://flakehub.com/f/nix-community/disko/1.13.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gitlab-ci = {
      url = "github:Platonic-Systems/gitlab-ci";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";

    fh.url = "https://flakehub.com/f/DeterminateSystems/fh/*";

    flake-checker.url = "https://flakehub.com/f/DeterminateSystems/flake-checker/*";
  };

  outputs = { self, nixpkgs, paradox, typed-screeps, secrix, disko, gitlab-ci, determinate, fh, flake-checker }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      # Every locked flake input source, recursively; baked into the VM
      # image so the guest's first `nix develop` fetches nothing.
      collectFlakeInputs = input:
        [ input ] ++ builtins.concatMap collectFlakeInputs
          (builtins.attrValues (input.inputs or { }));
      flakeInputSources =
        builtins.concatMap collectFlakeInputs (builtins.attrValues self.inputs);
      # Shared by nixosConfigurations.vm and checks.vm-boot.
      vmCoreModules = [
        determinate.nixosModules.default
        ./vm/module.nix
      ];
      paradoxBin = paradox.packages.${system}.paradox;
      # Atlas ships in the paradox flake source.
      atlas = "${paradox}/lib/dox";

      # Paradox generate writes into <spec-dir>/.dox/, so work on a copy.
      generated = pkgs.stdenv.mkDerivation {
        name = "dox-populi-generated";
        src = ./dox;
        nativeBuildInputs = [ paradoxBin pkgs.z3 ];
        PARADOX_ATLAS = atlas;
        LC_ALL = "C.UTF-8"; # GHC decodes source files per locale; sandbox has none
        buildPhase = ''
          cp -r . ../spec
          paradox generate --typescript --path ../spec
        '';
        installPhase = ''
          mkdir -p $out
          cp -r ../spec/.dox/. $out/
        '';
      };

      tsSrc = pkgs.runCommand "dox-populi-ts-src" { } ''
        mkdir -p $out/vendor
        cp -r ${./shell} $out/shell
        cp -r ${generated} $out/generated
        cp ${typed-screeps}/dist/index.d.ts $out/vendor/screeps.d.ts
        cp ${./tsconfig.json} $out/tsconfig.json
      '';

      main = pkgs.stdenv.mkDerivation {
        name = "dox-populi-main";
        src = tsSrc;
        nativeBuildInputs = [ pkgs.esbuild ];
        buildPhase = ''
          esbuild shell/main.ts --bundle --format=cjs --platform=node \
            --outfile=main.js
        '';
        installPhase = ''
          mkdir -p $out
          cp main.js $out/
        '';
      };

      # Raider brain (dox/invader spec + shell/invader.ts); apps.server
      # seeds it as the "raiders" NPC user's users.code.
      invaderMain = pkgs.stdenv.mkDerivation {
        name = "dox-populi-invader-main";
        src = tsSrc;
        nativeBuildInputs = [ pkgs.esbuild ];
        buildPhase = ''
          esbuild shell/invader.ts --bundle --format=cjs --platform=node \
            --outfile=invader.js
        '';
        installPhase = ''
          mkdir -p $out
          cp invader.js $out/
        '';
      };
      # Server mod (mods.json): replaces the native genInvaders cron with
      # the spec's genRaiders, which inserts "raiders"-owned creeps at
      # the room's exits when harvested energy crosses raidGoal
      # (room.invaderGoal override honored).
      raidMod = pkgs.stdenv.mkDerivation {
        name = "dox-populi-raid-mod";
        src = tsSrc;
        nativeBuildInputs = [ pkgs.esbuild ];
        buildPhase = ''
          esbuild shell/raidmod.ts --bundle --format=cjs --platform=node \
            --outfile=raidmod.js
        '';
        installPhase = ''
          mkdir -p $out
          cp raidmod.js $out/
        '';
      };
      secrixApp = secrix.secrix self;
      secrixCli = pkgs.writeShellApplication {
        name = "secrix";
        text = ''
          exec ${secrixApp.program} "$@"
        '';
      };

      # ms per tick (engine default 1000). setTickDuration persists in
      # world storage, so apps.server re-asserts this every launch;
      # SCREEPS_TICK_MS overrides per shell.
      tickMs = 50;

      # The open-source Screeps server, nix-vendored from npm. isolated-vm
      # and friends are native modules: node-gyp needs python + the
      # matching node headers.
      serverNode = pkgs.nodejs_22; # screeps@4.3.0 wants node >=22.9
      screepsServer = pkgs.buildNpmPackage {
        pname = "dox-populi-screeps-server";
        version = "4.3.0";
        src = ./server/npm;
        nodejs = serverNode;
        # Pinned by `nix run .#lock-server` (writes package-lock.json + this
        # hash file); rerun it whenever server/npm/package.json changes.
        npmDepsHash = pkgs.lib.trim (builtins.readFile ./server/npm/npm-deps-hash);
        # Lifecycle scripts invoke node_modules/.bin shims whose
        # `#!/usr/bin/env node` shebangs don't resolve in the sandbox:
        # install with scripts off, patch shebangs, then `npm rebuild`
        # runs them all (isolated-vm node-gyp, screeps postinstall webpack).
        npmFlags = [ "--ignore-scripts" ];
        preBuild = ''
          patchShebangs node_modules
          npm rebuild
        '';
        nativeBuildInputs = [ pkgs.python3 pkgs.pkg-config ];
        # screeps pins isolated-vm as a git dep (install scripts, no lockfile).
        forceGitDeps = true;
        makeCacheWritable = true;
        dontNpmBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r node_modules $out/
        '';
      };

      # Browser client bridge: screeps-steamless-client serves the official
      # client assets (from a Steam install of the GAME — proprietary, not
      # shipped) to a web browser, proxied to any private server. Pure-JS
      # deps, so plain vendoring.
      screepsClient = pkgs.buildNpmPackage {
        pname = "dox-populi-screeps-client";
        version = "1.2.1";
        src = ./client/npm;
        nodejs = serverNode;
        # Pinned by `nix run .#lock-client`.
        npmDepsHash = pkgs.lib.trim (builtins.readFile ./client/npm/npm-deps-hash);
        dontNpmBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r node_modules $out/
        '';
      };

      # Private-server mods, nix-vendored: deps declared in
      # server/mods/package.json, resolved by the committed package-lock.json,
      # fetched reproducibly via npmDepsHash. apps.server injects the mod
      # entry paths into the generated mods.json each launch.
      serverMods = pkgs.buildNpmPackage {
        pname = "dox-populi-server-mods";
        version = "1.0.0";
        src = ./server/mods;
        # Pinned by `nix run .#lock-mods` (writes package-lock.json + this
        # hash file); rerun it whenever server/mods/package.json changes.
        npmDepsHash = pkgs.lib.trim (builtins.readFile ./server/mods/npm-deps-hash);
        dontNpmBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r node_modules $out/
        '';
      };
    in
    {
      # Secrix key stub: the secrix CLI reads config.secrix from this
      # flake's nixosConfigurations.
      nixosConfigurations.dox-populi = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          secrix.nixosModules.default
          {
            secrix.defaultEncryptKeys.mlitchard = [
              (builtins.readFile ./secrets/public_keys/mlitchard.pub)
            ];
            # Dummy fs/bootloader satisfy flake-check asserts.
            fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
            boot.loader.grub.enable = false;
            system.stateVersion = "26.05";
          }
        ];
      };

      # Dev VM. Built into a raw disk image (packages.vm-image →
      # vm-image-zst) that the installer ISO dd's onto /dev/vda.
      # vm/disko.nix is a separate module so checks.vm-boot can boot
      # vmCoreModules without it.
      nixosConfigurations.vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = vmCoreModules ++ [
          disko.nixosModules.disko
          ./vm/disko.nix
          # Bake dev-shell outputs and all locked flake input sources
          # into the image so `nix develop` in the VM is offline. Lives
          # here because it needs `self`; vm/module.nix stays self-free
          # for tests/vm.nix.
          {
            system.extraDependencies = flakeInputSources ++ [
              self.devShells.${system}.default
              self.packages.${system}.screeps-server
              self.packages.${system}.screeps-client
            ];
          }
        ];
      };
      nixosConfigurations.installer = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { vmImageZst = self.packages.${system}.vm-image-zst; };
        modules = [ ./vm/installer.nix ];
      };

      packages.${system} = {
        inherit generated main;
        # Exported so CI builds them outside the itest job.
        invader-main = invaderMain;
        raid-mod = raidMod;
        screeps-server = screepsServer;
        screeps-client = screepsClient;
        secrix = secrixCli;
        default = main;
        # Raw disk image of the dev VM (disko image builder). Output:
        # <name>.raw per disk (vm/disko.nix names one disk, "main").
        vm-image =
          self.nixosConfigurations.vm.config.system.build.diskoImages;
        # zstd -3: ~100x faster than -19 for <3% size difference.
        vm-image-zst = pkgs.runCommand "dox-populi-vm-image-zst"
          { nativeBuildInputs = [ pkgs.zstd ]; } ''
          mkdir -p $out
          zstd -3 -T0 -v -o $out/image.raw.zst \
            ${self.packages.${system}.vm-image}/*.raw
        '';
        installer-iso =
          self.nixosConfigurations.installer.config.system.build.isoImage;
      };

      devShells.${system}.default = pkgs.mkShell {
        name = "dox-populi-dev";
        packages = [
          paradoxBin
          fh.packages.${system}.default
          flake-checker.packages.${system}.default
          pkgs.z3
          pkgs.nodejs
          pkgs.typescript
          pkgs.esbuild
          pkgs.jq
          pkgs.curl
          pkgs.nixpkgs-fmt
          self.packages.${system}.secrix
        ];
        PARADOX_ATLAS = atlas;
        shellHook = ''
          echo "dox-populi Development Shell"
          echo ""
          echo "Available commands:"
          echo "  paradox check --path dox      — verify the spec"
          echo "  secrix create|edit|rekey ...  — manage encrypted secrets"
          echo "  nix run .#generate            — write ./generated + ./vendor for editors"
          echo "  nix run .#deploy              — bundle and push main.js to Screeps"
          echo "  nix run .#server              — run the private Screeps server (Steam install)"
          echo "  nix run .#lock-mods           — re-pin server/mods (after editing its package.json)"
          echo "  nix run .#cli                 — connect to the private server CLI (21026)"
          echo "  nix run .#deploy-local        — push main.js to the private server (self-provisioning)"
          echo "  nix run .#client              — browser client on :8080 (needs Steam game files)"
          echo "  nix run .#stop                — stop server + client (world kept)"
          echo "  nix run .#reset-local         — stop server + wipe the private world"
          echo "  nix run .#itest               — VM integration test: deploy + spawn + harvest"
          echo "  nix run .#installer-iso       — provision the dev VM disk (one-time dd install)"
          echo "  ./run-vm.sh                   — run the installed dev VM"
          echo "  nix flake check               — run all checks"
        '';
      };

      checks.${system} = {
        # End-to-end VM test: server + deploy + harvest.
        itest = pkgs.callPackage ./tests/integration.nix {
          serverProgram = self.apps.${system}.server.program;
          deployProgram = self.apps.${system}.deploy-local.program;
          inherit tickMs;
        };

        # First-boot contract of the dev VM (vmCoreModules): repo
        # mount, sshd, Determinate Nix, flakes, dev env vars.
        vm-boot = pkgs.callPackage ./tests/vm.nix {
          nixosModule = { imports = vmCoreModules; };
          inherit self;
        };

        paradox-check = pkgs.runCommand "paradox-check"
          {
            nativeBuildInputs = [ paradoxBin pkgs.z3 ];
            PARADOX_ATLAS = atlas;
            LC_ALL = "C.UTF-8";
          } ''
          cp -r ${./dox} spec
          chmod -R u+w spec
          paradox check --path spec
          touch $out
        '';

        typecheck = pkgs.runCommand "typecheck"
          { nativeBuildInputs = [ pkgs.typescript ]; } ''
          cp -r ${tsSrc}/. .
          tsc --noEmit -p tsconfig.json
          touch $out
        '';

        # Exhaustive sweep of the generated transition functions
        # against the restated policy.
        fsm-behavior = pkgs.runCommand "fsm-behavior"
          { nativeBuildInputs = [ pkgs.typescript pkgs.nodejs_22 ]; } ''
          cp -r ${tsSrc}/. .
          mkdir -p tests
          cp ${./tests/fsm-behavior.ts} tests/fsm-behavior.ts
          cat > tsconfig.test.json <<'CONF'
          {
            "compilerOptions": {
              "target": "ES2019",
              "module": "commonjs",
              "moduleResolution": "node",
              "strict": true,
              "esModuleInterop": true,
              "skipLibCheck": true,
              "outDir": "out"
            },
            "include": [
              "generated/**/*.ts",
              "tests/fsm-behavior.ts"
            ]
          }
          CONF
          tsc -p tsconfig.test.json
          node out/tests/fsm-behavior.js
          touch $out
        '';

        build = main;
      };

      # CI job filter, read by the gitlab-ci.nix generator (`flake.gitlab
      # or null`, applied to the generated config). The generator maps
      # every flake output to a job; one job building the deepest
      # artifact proves the whole chain. Dropped:
      # - VM chain: apps:installer-iso embeds vm-image-zst <- vm-image
      #   <- the vm system, so those upstream jobs are redundant.
      # - checks:build and packages:main are the same derivation as
      #   packages:default.
      # - flake:check rebuilds every check the test stage already ran.
      # - flake:show: gitlab-ci:check runs `nix flake show --json` itself.
      # - apps:server / apps:deploy-local are baked into checks:itest
      #   (serverProgram/deployProgram).
      # removeAttrs, not `= null` (nulls survive into the YAML), plus a
      # needs scrub (GitLab rejects undefined needs).
      gitlab = prev:
        let
          dropped = [
            "nixosConfigurations:vm"
            "nixosConfigurations:installer"
            "packages:vm-image"
            "packages:vm-image-zst"
            "packages:installer-iso"
            "checks:build"
            "packages:main"
            "flake:check"
            "flake:show"
            "apps:server"
            "apps:deploy-local"
          ];
          scrubNeeds = _: job:
            if builtins.isAttrs job && job ? needs
            then job // {
              needs = builtins.filter (n: !(builtins.elem n dropped)) job.needs;
            }
            else job;
          filtered = builtins.mapAttrs scrubNeeds (builtins.removeAttrs prev dropped);
        # FlakeHub publishing lives in GitHub Actions
        # (.github/workflows/flakehub.yml): FlakeHub trusts github.com's
        # OIDC issuer, not this GitLab instance's.
        in filtered;

      apps.${system} = {
        # Regenerate ./generated and ./vendor in the working tree for editor use.
        generate = {
          type = "app";
          program = toString (pkgs.writeShellScript "generate" ''
            set -euo pipefail
            rm -rf generated vendor
            mkdir -p generated vendor
            cp -r ${generated}/. generated/
            cp ${typed-screeps}/dist/index.d.ts vendor/screeps.d.ts
            chmod -R u+w generated vendor
            echo "wrote ./generated and ./vendor/screeps.d.ts"
          '');
        };

        # Human-gated deploy: decrypting the token requires the SSH private key.
        deploy = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy" ''
            set -euo pipefail
            IDENTITY="''${SCREEPS_IDENTITY:-''${WORKDIR:-''${HOME:-/root}/work}/identity}"
            if [ ! -f "$IDENTITY" ]; then
              echo "error: no identity key at $IDENTITY (needed to decrypt secrets/SCREEPS_TOKEN)" >&2
              echo "place YOUR key there, or set SCREEPS_IDENTITY=/path/to/your/key" >&2
              exit 1
            fi
            TOKEN=$(${secrixCli}/bin/secrix decrypt secrets/SCREEPS_TOKEN -i "$IDENTITY")
            ${pkgs.jq}/bin/jq -n --arg code "$(cat ${main}/main.js)" \
              '{branch: "default", modules: {main: $code}}' \
            | ${pkgs.curl}/bin/curl --fail-with-body -X POST \
                "https://screeps.com/api/user/code" \
                -H "X-Token: $TOKEN" \
                -H "Content-Type: application/json" \
                --data @-
            echo
            echo "deployed main.js to branch 'default'"
          '');
        };

        # Run the private Screeps server (nix-vendored open-source npm
        # package — no Steam install needed). Game state lives in
        # ./.server-data/ (gitignored); .screepsrc is regenerated each
        # launch from server/screepsrc with the Steam Web API key injected
        # from secrets/STEAM_TOKEN (used only to authenticate Steam-client
        # players — the server itself runs without Steam).
        server = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-server" ''
            set -euo pipefail
            # Flake default; SCREEPS_TICK_MS is an optional override.
            # The value is spliced into a CLI expression — digits only.
            TICK_MS="''${SCREEPS_TICK_MS:-${toString tickMs}}"
            case "$TICK_MS" in
              ("" | *[!0-9]*)
                echo "error: SCREEPS_TICK_MS must be digits only (milliseconds per tick), got: '$TICK_MS'" >&2
                exit 1 ;;
            esac
            LAUNCHER="${screepsServer}/node_modules/@screeps/launcher"
            # Anchor to the repo root regardless of launch cwd — a stray
            # $PWD/.server-data means a parallel world with its own db.
            DATA="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
            # Identity for secrix decryption: SCREEPS_IDENTITY override,
            # else the conventional location of the USER-PROVIDED key —
            # "identity" in the shared work dir (the VM's run-vm.sh
            # WORKDIR share). No particular key is shipped or assumed.
            IDENTITY="''${SCREEPS_IDENTITY:-''${WORKDIR:-''${HOME:-/root}/work}/identity}"

            # Env override first (the VM test passes a dummy key: any
            # non-empty STEAM_KEY disables greenworks/native Steam auth),
            # then secrix.
            STEAM_API_KEY="''${STEAM_API_KEY:-}"
            if [ -z "$STEAM_API_KEY" ] && [ -f secrets/STEAM_TOKEN ]; then
              if [ ! -f "$IDENTITY" ]; then
                echo "error: secrets/STEAM_TOKEN exists but no identity key at $IDENTITY" >&2
                echo "place YOUR key there, or set SCREEPS_IDENTITY=/path/to/your/key" >&2
                exit 1
              fi
              STEAM_API_KEY=$(${secrixCli}/bin/secrix decrypt secrets/STEAM_TOKEN -i "$IDENTITY")
            fi
            if [ -z "$STEAM_API_KEY" ]; then
              echo "note: no Steam Web API key; starting without Steam auth" >&2
              echo "      create it with:" >&2
              echo "      echo -n 'KEY' | nix run .#secrix encrypt ./secrets/STEAM_TOKEN -- --all-users" >&2
            fi

            mkdir -p "$DATA/logs"
            [ -e "$DATA/assets" ]       || ln -s "$LAUNCHER/init_dist/assets" "$DATA/assets"
            [ -e "$DATA/node_modules" ] || ln -s "$LAUNCHER/init_dist/node_modules" "$DATA/node_modules"
            # mods.json is regenerated every launch: the versioned
            # template plus nix-vendored mod paths. raidmod replaces the
            # native genInvaders cron with the spec-driven raid policy.
            ${pkgs.jq}/bin/jq --arg auth "${serverMods}/node_modules/screepsmod-auth/index.js" \
              --arg raid "${raidMod}/raidmod.js" \
              '.mods += [$auth, $raid]' ${./server/mods.json} > "$DATA/mods.json.tmp"
            mv -f "$DATA/mods.json.tmp" "$DATA/mods.json"
            # Seed the world database on first run (screeps init's job).
            # -s: also replace a 0-byte stub left by a failed GUI launch.
            if [ ! -s "$DATA/db.json" ]; then
              cp "$LAUNCHER/init_dist/db.json" "$DATA/db.json"
              chmod u+w "$DATA/db.json"
              # Seed a dedicated NPC user ("raiders") with the raider
              # brain (dox/invader → shell/invader.ts → invaderMain).
              # Not uid 2: the engine drives user-2 creeps itself and
              # never runs its users.code, and uid 2 owns a stock
              # stronghold that muddies combat probes. The doc mirrors a
              # simplebot user; the meta field is required — the LokiJS
              # storage layer throws on any update to a doc without one.
              # `active`
              # is server-managed, so the seeded value is only a
              # default. The uid-2 empty users.code stub prevents
              # "Unknown module 'main'" spam when the server activates
              # that user. An existing world keeps its db until
              # reset-local.
              ${pkgs.jq}/bin/jq --rawfile invader ${invaderMain}/invader.js \
                '(.collections[] | select(.name == "users")) |= (.data += [{_id: "raiders", username: "Raiders", usernameLower: "raiders", cpu: 100, cpuAvailable: 10000, active: true, gcl: 1, registeredDate: "2016-11-14T14:04:21.156Z", badge: {type: 1, color1: "#f00", color2: "#000", color3: "#f00", flip: false, param: 0}, meta: {revision: 0, created: 0, version: 0}, "$loki": (.maxId + 1)}] | .maxId += 1)
                 | (.collections[] | select(.name == "users.code")) |= (.data += [{_id: "RaiderCode", user: "raiders", branch: "default", activeWorld: true, modules: {main: $invader}, meta: {revision: 0, created: 0, version: 0}, "$loki": (.maxId + 1)}, {_id: "InvaderStub", user: "2", branch: "default", activeWorld: true, modules: {main: "module.exports.loop = function () {};"}, meta: {revision: 0, created: 0, version: 0}, "$loki": (.maxId + 2)}] | .maxId += 2)' \
                "$DATA/db.json" > "$DATA/db.json.tmp"
              mv -f "$DATA/db.json.tmp" "$DATA/db.json"
            fi
            # Bind address knob: loopback by default; the VM sets
            # SCREEPS_HOST=0.0.0.0 so qemu's port forwards can reach it.
            SCREEPS_HOST="''${SCREEPS_HOST:-127.0.0.1}"
            ${pkgs.gnused}/bin/sed \
              -e "s|^steam_api_key =.*|steam_api_key = $STEAM_API_KEY|" \
              -e "s|^host =.*|host = $SCREEPS_HOST|" \
              -e "s|^cli_host =.*|cli_host = $SCREEPS_HOST|" \
              ${./server/screepsrc} > "$DATA/.screepsrc"

            echo "screeps private server: http://$SCREEPS_HOST:21025 (cli on $SCREEPS_HOST:21026)"
            echo "tick duration: $TICK_MS ms/tick (flake default ${toString tickMs}; override with SCREEPS_TICK_MS) — re-asserted on every launch"
            echo "data dir: $DATA"
            cd "$DATA"
            # Mods live in the nix store, but require() the server's own
            # @screeps/* packages. Node honors NODE_PATH, and the launcher
            # passes its env to every child process.
            export NODE_PATH="${screepsServer}/node_modules"
            # Headless launch: the launcher CLI's `start` reads ./.screepsrc
            # from cwd and spawns storage/backend/engine children via
            # process.execPath. The children survive the launcher's death,
            # leaving 21025/21026 bound — so run the launcher in the
            # background and sweep the whole tree (every process has the
            # vendored server's store path in its argv) on ANY exit,
            # including Ctrl-C.
            cleanup() {
              [ -n "''${TICK_PID:-}" ] && kill "$TICK_PID" 2>/dev/null || true
              ${pkgs.procps}/bin/pkill -TERM -f '${screepsServer}/node_modules' 2>/dev/null || true
              sleep 2
              ${pkgs.procps}/bin/pkill -9 -f '${screepsServer}/node_modules' 2>/dev/null || true
            }
            trap cleanup EXIT
            ${serverNode}/bin/node "$LAUNCHER/bin/screeps.js" start "$@" &
            LAUNCHER_PID=$!
            # Assert the tick duration once the CLI answers (21026 may
            # not be bound yet — poll by pushing the command itself; nc
            # fails fast on a closed port). setTickDuration persists in
            # the world's env storage, so this re-asserts it every
            # launch. Best-effort: a miss means wrong tick speed, never
            # a dead server.
            (
              for _ in $(seq 1 60); do
                if printf 'system.setTickDuration(%s)\n' "$TICK_MS" \
                     | ${pkgs.netcat-openbsd}/bin/nc -q 2 127.0.0.1 21026 >/dev/null 2>&1; then
                  echo "tick duration set: $TICK_MS ms/tick"
                  exit 0
                fi
                sleep 2
              done
              echo "warning: CLI (21026) never answered — tick duration NOT set (world keeps its stored rate)" >&2
            ) &
            TICK_PID=$!
            wait "$LAUNCHER_PID" || true
          '');
        };

        # Resolve + pin the private-server mod set: regenerates
        # server/mods/package-lock.json from package.json, computes the
        # npmDepsHash with nixpkgs' own prefetch-npm-deps, and stages the
        # results so the flake can see them. The only time npm's resolver
        # runs — everything downstream is pure nix. Rerun after editing
        # server/mods/package.json.
        lock-mods = {
          type = "app";
          program = toString (pkgs.writeShellScript "lock-mods" ''
            set -euo pipefail
            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)/server/mods"
            ${pkgs.nodejs}/bin/npm install --package-lock-only --ignore-scripts --no-audit --no-fund
            ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps package-lock.json > npm-deps-hash
            ${pkgs.git}/bin/git add package.json package-lock.json npm-deps-hash
            echo "pinned: server/mods/package-lock.json + npm-deps-hash (staged; commit when ready)"
          '');
        };

        # Same pinning flow for the server package itself. Rerun after
        # editing server/npm/package.json.
        lock-server = {
          type = "app";
          program = toString (pkgs.writeShellScript "lock-server" ''
            set -euo pipefail
            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)/server/npm"
            ${serverNode}/bin/npm install --package-lock-only --ignore-scripts --no-audit --no-fund
            # isolated-vm is a git dep with install scripts; see forceGitDeps
            # on the screepsServer derivation.
            FORCE_GIT_DEPS=1 ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps package-lock.json > npm-deps-hash
            ${pkgs.git}/bin/git add package.json package-lock.json npm-deps-hash
            echo "pinned: server/npm/package-lock.json + npm-deps-hash (staged; commit when ready)"
          '');
        };

        # Same pinning flow for the browser-client bridge. Rerun after
        # editing client/npm/package.json.
        lock-client = {
          type = "app";
          program = toString (pkgs.writeShellScript "lock-client" ''
            set -euo pipefail
            cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)/client/npm"
            ${serverNode}/bin/npm install --package-lock-only --ignore-scripts --no-audit --no-fund
            ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps package-lock.json > npm-deps-hash
            ${pkgs.git}/bin/git add package.json package-lock.json npm-deps-hash
            echo "pinned: client/npm/package-lock.json + npm-deps-hash (staged; commit when ready)"
          '');
        };

        # Browser client: serve the official client assets from the local
        # Steam install of the game (package.nw — you must own Screeps) and
        # proxy to the private server. Open
        #   http://127.0.0.1:8080/(http://127.0.0.1:21025)/
        # and sign in with your deploy-local credentials (screepsmod-auth).
        client = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-client" ''
            set -euo pipefail
            # Asset search order: explicit override, then the shared work
            # dir (VM users copy package.nw there from the host's Steam
            # install — same convention as the identity key), then the
            # local Steam install.
            NW="''${SCREEPS_CLIENT_NW:-}"
            if [ -z "$NW" ]; then
              for CAND in "''${WORKDIR:-''${HOME:-/root}/work}/package.nw" \
                          "$HOME/.local/share/Steam/steamapps/common/Screeps/package.nw"; do
                if [ -f "$CAND" ]; then NW="$CAND"; break; fi
              done
            fi
            if [ -z "$NW" ] || [ ! -f "$NW" ]; then
              echo "error: client assets (package.nw) not found; looked at:" >&2
              echo "  \$SCREEPS_CLIENT_NW (unset or missing)" >&2
              echo "  ''${WORKDIR:-''${HOME:-/root}/work}/package.nw (the shared work dir)" >&2
              echo "  $HOME/.local/share/Steam/steamapps/common/Screeps/package.nw" >&2
              echo "install the Screeps game via Steam, copy its package.nw into the shared work dir, or set SCREEPS_CLIENT_NW=/path/to/package.nw" >&2
              exit 1
            fi
            # Bind address: explicit override, else follow the server's
            # knob (the VM sets SCREEPS_HOST=0.0.0.0 so qemu's port
            # forwards reach it), else explicit IPv4 loopback — bare
            # "localhost" resolves to ::1 only, which browsers hitting
            # 127.0.0.1 can't reach.
            CLIENT_HOST="''${SCREEPS_CLIENT_HOST:-''${SCREEPS_HOST:-127.0.0.1}}"
            echo "client assets: $NW"
            echo "browser client: http://127.0.0.1:8080/(http://127.0.0.1:21025)/"
            exec ${serverNode}/bin/node \
              "${screepsClient}/node_modules/screeps-steamless-client/dist/index.js" \
              --package "$NW" --host "$CLIENT_HOST" "$@"
          '');
        };

        # Stop the private server (the launcher and its children all
        # carry the vendored server's store path in argv) and the
        # browser client. World data is left intact.
        stop = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-stop" ''
            set -euo pipefail
            PKILL=${pkgs.procps}/bin/pkill
            if $PKILL -f '${screepsServer}/node_modules'; then
              sleep 2
              $PKILL -9 -f '${screepsServer}/node_modules' 2>/dev/null || true
              echo "server stopped"
            else
              echo "no server running"
            fi
            if $PKILL -f screeps-steamless-client; then
              echo "client stopped"
            else
              echo "no client running"
            fi
          '');
        };

        # Wipe the private-server world. The data dir regenerates from the
        # seed database on the next `nix run .#server`.
        reset-local = {
          type = "app";
          program = toString (pkgs.writeShellScript "reset-local" ''
            set -euo pipefail
            DATA="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
            # Same kill handle as apps.stop.
            ${pkgs.procps}/bin/pkill -f '${screepsServer}/node_modules' 2>/dev/null || true
            sleep 2
            ${pkgs.procps}/bin/pkill -9 -f '${screepsServer}/node_modules' 2>/dev/null || true
            rm -rf "$DATA"
            echo "world reset: $DATA removed (fresh world on next nix run .#server)"
          '');
        };

        # Provision the dev VM disk (one-time): create dox-populi.qcow2
        # and boot the installer ISO in qemu; its boot service dd's the
        # prebuilt image onto the disk and powers off (vm/installer.nix).
        # No -netdev: the installer needs no network. ./run-vm.sh runs
        # the installed VM. `nix run .#installer-iso` resolves to this
        # app; `nix build .#installer-iso` builds the bare ISO package.
        installer-iso = {
          type = "app";
          program = toString (pkgs.writeShellScript "install-vm" ''
            set -euo pipefail
            DISK="''${DISK:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/dox-populi.qcow2}"
            DISK_SIZE="''${DISK_SIZE:-40G}"
            MEM="''${MEM:-4G}"
            CPUS="''${CPUS:-4}"
            if [ -f "$DISK" ]; then
              echo "error: $DISK already exists — the VM is already installed." >&2
              echo "run it with ./run-vm.sh, or delete the disk for a factory reset." >&2
              exit 1
            fi
            ISO=$(set -- ${self.packages.${system}.installer-iso}/iso/*.iso; echo "$1")
            ACCEL=()
            if [ -w /dev/kvm ]; then
              ACCEL=(-enable-kvm -cpu host)
            else
              echo "warning: /dev/kvm not writable — running unaccelerated (slow)" >&2
            fi
            ${pkgs.qemu}/bin/qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
            echo "created $DISK ($DISK_SIZE) — booting the installer (dd, grow, poweroff)..."
            ${pkgs.qemu}/bin/qemu-system-x86_64 \
              "''${ACCEL[@]}" \
              -m "$MEM" -smp "$CPUS" \
              -drive "file=$DISK,if=virtio,format=qcow2" \
              -cdrom "$ISO" -boot d \
              -display none \
              -serial mon:stdio \
              || { echo "error: installer qemu exited abnormally — delete $DISK and retry" >&2; exit 1; }
            echo ""
            echo "install complete — boot the dev VM with ./run-vm.sh"
          '');
        };

        # Connect to the private server's CLI (port 21026). Use it to manage
        # the running server, e.g. setPassword('YourUsername', 'password').
        cli = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-cli" ''
            set -euo pipefail
            exec ${serverNode}/bin/node \
              "${screepsServer}/node_modules/@screeps/launcher/bin/screeps.js" cli "$@"
          '');
        };

        # Push main.js to the private server (default http://127.0.0.1:21025),
        # self-provisioning: if signin fails it sets the account password via
        # the server CLI and retries; after deploy it auto-places Spawn1 if
        # the account owns nothing. Only account creation itself is manual
        # (once per world, in the Steam client — binds your Steam identity).
        # Credentials come from env vars, or from age-encrypted
        # secrets/SCREEPS_LOCAL_CREDS containing one line "username:password":
        #   secrix create secrets/SCREEPS_LOCAL_CREDS -i <your-key> -r "$(cat <your-key>.pub)"
        deploy-local = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy-local" ''
            set -euo pipefail
            URL="''${SCREEPS_LOCAL_URL:-http://127.0.0.1:21025}"
            # Identity for secrix decryption: SCREEPS_IDENTITY override,
            # else the conventional location of the USER-PROVIDED key.
            IDENTITY="''${SCREEPS_IDENTITY:-''${WORKDIR:-''${HOME:-/root}/work}/identity}"

            if { [ -z "''${SCREEPS_LOCAL_EMAIL:-}" ] || [ -z "''${SCREEPS_LOCAL_PASSWORD:-}" ]; } \
               && [ -f secrets/SCREEPS_LOCAL_CREDS ]; then
              if [ ! -f "$IDENTITY" ]; then
                echo "error: secrets/SCREEPS_LOCAL_CREDS exists but no identity key at $IDENTITY" >&2
                echo "place YOUR key there, or set SCREEPS_IDENTITY=/path/to/your/key" >&2
                exit 1
              fi
              CREDS=$(${secrixCli}/bin/secrix decrypt secrets/SCREEPS_LOCAL_CREDS -i "$IDENTITY")
              SCREEPS_LOCAL_EMAIL="''${SCREEPS_LOCAL_EMAIL:-''${CREDS%%:*}}"
              SCREEPS_LOCAL_PASSWORD="''${SCREEPS_LOCAL_PASSWORD:-''${CREDS#*:}}"
            fi
            : "''${SCREEPS_LOCAL_EMAIL:?set SCREEPS_LOCAL_EMAIL or create secrets/SCREEPS_LOCAL_CREDS}"
            : "''${SCREEPS_LOCAL_PASSWORD:?set SCREEPS_LOCAL_PASSWORD or create secrets/SCREEPS_LOCAL_CREDS}"

            CURL="${pkgs.curl}/bin/curl"
            JQ="${pkgs.jq}/bin/jq"
            CLI_HOST="''${SCREEPS_LOCAL_CLI_HOST:-127.0.0.1}"
            CLI_PORT="''${SCREEPS_LOCAL_CLI_PORT:-21026}"

            signin() {
              BODY=$($CURL -sS -X POST "$URL/api/auth/signin" \
                -H "Content-Type: application/json" \
                --data "$($JQ -n --arg e "$SCREEPS_LOCAL_EMAIL" --arg p "$SCREEPS_LOCAL_PASSWORD" \
                  '{email: $e, password: $p}')")
              TOKEN=$(printf '%s' "$BODY" | $JQ -r '.token // empty' 2>/dev/null || true)
            }

            signin
            if [ -z "$TOKEN" ]; then
              # Self-provision (CI-friendly): register the account outright —
              # screepsmod-auth's /api/register/submit creates user+password
              # with no Steam involvement. If the account already exists,
              # push the password via the server CLI instead. Retry once.
              echo "signin failed — provisioning account '$SCREEPS_LOCAL_EMAIL'" >&2
              $CURL -sS -X POST "$URL/api/register/submit" \
                -H "Content-Type: application/json" \
                --data "$($JQ -n --arg u "$SCREEPS_LOCAL_EMAIL" --arg p "$SCREEPS_LOCAL_PASSWORD" \
                  '{username: $u, password: $p}')" >/dev/null 2>&1 || true
              $JQ -rn --arg u "$SCREEPS_LOCAL_EMAIL" --arg p "$SCREEPS_LOCAL_PASSWORD" \
                '"auth.setPassword(\($u|@json), \($p|@json))"' \
                | ${pkgs.netcat-openbsd}/bin/nc -q 2 "$CLI_HOST" "$CLI_PORT" >/dev/null 2>&1 || true
              signin
            fi
            if [ -z "$TOKEN" ]; then
              echo "error: signin failed at $URL/api/auth/signin" >&2
              echo "server response: $BODY" >&2
              echo "(server running? screepsmod-auth loaded? account created in the client?)" >&2
              exit 1
            fi

            $JQ -n --arg code "$(cat ${main}/main.js)" \
              '{branch: "default", modules: {main: $code}}' \
            | $CURL --fail-with-body -sS -X POST "$URL/api/user/code" \
                -H "X-Token: $TOKEN" -H "Content-Type: application/json" --data @-
            echo
            echo "deployed main.js to $URL (branch 'default')"

            # Auto-spawn: if the account owns nothing yet, place Spawn1.
            # place-spawn demands a room that exists in db.rooms AND has
            # an unowned controller (the server's world-start-room falls
            # back to W5N5, a controller-less center room). No HTTP
            # endpoint exposes controller ownership, so read candidates
            # from the world db and try them in order.
            STATUS=$($CURL -sS -H "X-Token: $TOKEN" "$URL/api/user/world-status" \
              | $JQ -r '.status // empty')
            echo "world-status: $STATUS"
            if [ "$STATUS" = "lost" ]; then
              # Owns objects but no spawn+controller pair (spawn destroyed,
              # or leftovers from an earlier session). Respawn releases the
              # old objects and resets the account to "empty".
              $CURL -sS -X POST -H "X-Token: $TOKEN" "$URL/api/user/respawn" >/dev/null
              STATUS=$($CURL -sS -H "X-Token: $TOKEN" "$URL/api/user/world-status" \
                | $JQ -r '.status // empty')
              echo "respawned — world-status now: $STATUS"
            fi
            if [ "$STATUS" = "empty" ]; then
              if [ -n "''${SCREEPS_LOCAL_ROOM:-}" ]; then
                CANDIDATES="$SCREEPS_LOCAL_ROOM"
              else
                DATA="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
                CANDIDATES=$($JQ -r '.collections[] | select(.name == "rooms.objects")
                  | .data[]
                  | select(.type == "controller"
                           and ((.user // "") == "")
                           and ((.reservation // null) == null))
                  | .room' "$DATA/db.json")
              fi
              PLACED=
              for ROOM in $CANDIDATES; do
                TERRAIN=$($CURL -sS "$URL/api/game/room-terrain?room=$ROOM&encoded=true" \
                  | $JQ -r '.terrain[0].terrain')
                IDX=$(${pkgs.gawk}/bin/awk -v s="$TERRAIN" 'BEGIN {
                  for (d = 0; d <= 1250; d++) for (k = 1; k >= -1; k -= 2) {
                    i = 1275 + d * k
                    if (i < 0 || i >= 2500) continue
                    ch = substr(s, i + 1, 1); x = i % 50; y = int(i / 50)
                    # 0 = plain, 2 = swamp (buildable); keep off the room edges
                    if ((ch == "0" || ch == "2") && x > 2 && x < 47 && y > 2 && y < 47) {
                      print i; exit
                    }
                  }
                }')
                [ -z "$IDX" ] && continue
                X=$((IDX % 50)); Y=$((IDX / 50))
                RESULT=$($CURL -sS -X POST "$URL/api/game/place-spawn" \
                  -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
                  --data "$($JQ -n --arg r "$ROOM" --argjson x "$X" --argjson y "$Y" \
                    '{room: $r, x: $x, y: $y, name: "Spawn1"}')")
                if [ "$(printf '%s' "$RESULT" | $JQ -r '.ok // empty')" = "1" ]; then
                  echo "auto-placed Spawn1 in $ROOM at ($X,$Y)"
                  # place-spawn welds newbie protection onto the room:
                  # safeMode (kept) and invaderGoal: 1000000. The raid
                  # mod honors per-room invaderGoal overrides, so clear
                  # it; raidWave: 0 resets the escalation counter.
                  # Best-effort: worst case is late raids, never a
                  # failed deploy.
                  $JQ -rn --arg r "$ROOM" \
                    '"storage.db.rooms.update({_id: \($r|@json)}, {$set: {invaderGoal: null, raidWave: 0}})"' \
                    | ${pkgs.netcat-openbsd}/bin/nc -q 2 "$CLI_HOST" "$CLI_PORT" >/dev/null 2>&1 || true
                  PLACED=1
                  break
                fi
                echo "place-spawn in $ROOM refused: $RESULT — trying next room" >&2
              done
              if [ -z "$PLACED" ]; then
                echo "error: auto-spawn failed — no candidate room accepted a spawn" >&2
                exit 1
              fi
            fi
          '');
        };

        # Build checks.itest with streamed logs.
        itest = {
          type = "app";
          program = toString (pkgs.writeShellScript "itest" ''
            set -euo pipefail
            exec nix build -L --no-link \
              "$(${pkgs.git}/bin/git rev-parse --show-toplevel)#checks.${system}.itest" "$@"
          '');
        };

        secrix = secrix.secrix self;

        # Regenerate CI config: nix run .#gitlab-ci > .gitlab-ci.yml
        gitlab-ci = gitlab-ci.apps.${system}.gitlab-ci;
      };

    };
}
