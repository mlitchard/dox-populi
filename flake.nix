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
  };

  outputs = { self, nixpkgs, paradox, typed-screeps, secrix }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # steam-run (unfree) launches the private Screeps server.
        config.allowUnfreePredicate =
          pkg: nixpkgs.lib.hasPrefix "steam" (nixpkgs.lib.getName pkg);
      };
      paradoxBin = paradox.packages.${system}.paradox;
      # Atlas lives in the paradox *source* (the flake input), not the
      # installed package output.
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

      # Assemble the full TS project (shell + generated + vendored types).
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
      # secrix CLI as a devShell command (llm-core pattern: tool packages
      # included in devShell packages, not reached via `nix run`).
      secrixApp = secrix.secrix self;
      secrixCli = pkgs.writeShellApplication {
        name = "secrix";
        text = ''
          exec ${secrixApp.program} "$@"
        '';
      };

      # NW.js runtime libraries needed by the Steam-bundled screeps_server
      # binary. Mirrors nwjs-env from nixpkgs' nwjs package.
      screepsNwEnv = pkgs.buildEnv {
        name = "screeps-nw-env";
        paths = with pkgs; [
          alsa-lib
          at-spi2-core
          atk
          cairo
          cups
          dbus
          expat
          fontconfig
          freetype
          gdk-pixbuf
          glib
          gtk3
          libcap
          libdrm
          libGL
          libnotify
          libxkbcommon
          libgbm
          nspr
          nss
          pango
          libx11
          libxscrnsaver
          libxcomposite
          libxcursor
          libxdamage
          libxext
          libxfixes
          libxi
          libxrandr
          libxrender
          libxtst
          libxshmfence
          ffmpeg
          libxcb
          libuuid
          sqlite
          udev
        ];
        extraOutputsToInstall = [ "lib" "out" ];
      };

      # steam-run FHS env extended with the NW.js libraries — the launcher
      # for screeps_server. Same pattern as NixOS-Configuration's steamcmd
      # game servers (dragonwilds/terratech run servers via pkgs.steam-run).
      screepsServerRun = (pkgs.steam.override {
        extraPkgs = _: [ screepsNwEnv ];
      }).run;

      # The launcher UI does require('npm') for mod management. npm 6 is the
      # last release with the programmatic API it expects; hash-pinned (quux
      # pattern: nix owns npm deps). npm ships its own deps bundled, so
      # unpacking the tarball is the complete installation.
      npm6 = pkgs.stdenv.mkDerivation {
        name = "npm-6.14.18-module";
        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/npm/-/npm-6.14.18.tgz";
          hash = "sha256-ybFfJ34qCxtX4FutBFBClqJwJFVdVsKqln+GLpV60u0=";
        };
        dontBuild = true;
        installPhase = ''
          mkdir -p $out/lib/node_modules/npm
          cp -r . $out/lib/node_modules/npm/
        '';
      };

      # Private-server mods, nix-vendored (quux pattern): deps declared in
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
      # Self-contained secrix key configuration. The secrix CLI derives its
      # users and systems from config.secrix across this flake's
      # nixosConfigurations — keys are declared here, not in ~/nixos.
      nixosConfigurations.dox-populi = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          secrix.nixosModules.default
          {
            secrix.defaultEncryptKeys.mlitchard = [
              (builtins.readFile ./secrets/public_keys/mlitchard.pub)
            ];
          }
        ];
      };

      packages.${system} = {
        inherit generated main;
        secrix = secrixCli;
        default = main;
      };

      devShells.${system}.default = pkgs.mkShell {
        name = "dox-populi-dev";
        packages = [
          paradoxBin
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
          echo "  nix run .#reset-local         — stop server + wipe the private world"
          echo "  nix flake check               — run all checks"
        '';
      };

      checks.${system} = {
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

        build = main;
      };

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
            TOKEN=$(${secrixCli}/bin/secrix decrypt secrets/SCREEPS_TOKEN -i "$HOME/.ssh/gitlab")
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

        # Run the private Screeps server bundled with the local Steam
        # install. Game state lives in ./.server-data/ (gitignored);
        # .screepsrc is regenerated each launch from server/screepsrc with
        # the Steam Web API key injected from secrets/steam-api-key.
        server = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-server" ''
            set -euo pipefail
            STEAM_SCREEPS="''${STEAM_SCREEPS_DIR:-$HOME/.local/share/Steam/steamapps/common/Screeps/server}"
            # Anchor to the repo root regardless of launch cwd — a stray
            # $PWD/.server-data means a parallel world with its own db.
            DATA="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
            IDENTITY="''${SCREEPS_IDENTITY:-$HOME/.ssh/gitlab}"

            if [ ! -x "$STEAM_SCREEPS/resources/node" ]; then
              echo "error: bundled node not found at $STEAM_SCREEPS/resources/node" >&2
              echo "install Screeps via Steam, or set STEAM_SCREEPS_DIR" >&2
              exit 1
            fi

            STEAM_API_KEY=""
            if [ -f secrets/STEAM_TOKEN ]; then
              STEAM_API_KEY=$(${secrixCli}/bin/secrix decrypt secrets/STEAM_TOKEN -i "$IDENTITY")
            else
              echo "note: secrets/STEAM_TOKEN not found; starting without Steam auth" >&2
              echo "      create it with:" >&2
              echo "      echo -n 'KEY' | nix run .#secrix encrypt ./secrets/STEAM_TOKEN -- --all-users" >&2
            fi

            mkdir -p "$DATA/logs"
            [ -e "$DATA/assets" ]       || ln -s "$STEAM_SCREEPS/assets" "$DATA/assets"
            [ -e "$DATA/node_modules" ] || ln -s "$STEAM_SCREEPS/node_modules" "$DATA/node_modules"
            # mods.json is regenerated every launch (like .screepsrc): the
            # versioned template plus nix-vendored mod entry paths.
            ${pkgs.jq}/bin/jq --arg auth "${serverMods}/node_modules/screepsmod-auth/index.js" \
              '.mods += [$auth]' ${./server/mods.json} > "$DATA/mods.json.tmp"
            mv -f "$DATA/mods.json.tmp" "$DATA/mods.json"
            # Seed the world database on first run (screeps init's job).
            # -s: also replace a 0-byte stub left by a failed GUI launch.
            if [ ! -s "$DATA/db.json" ]; then
              cp "$STEAM_SCREEPS/package/node_modules/@screeps/launcher/init_dist/db.json" "$DATA/db.json"
              chmod u+w "$DATA/db.json"
              # Give the NPC Invader user (id 2) an empty script in the seed:
              # without one, engine_runner spams "Unknown module 'main'"
              # every tick. Patched offline so no runtime step is needed.
              ${pkgs.jq}/bin/jq '(.collections[] | select(.name == "users.code")) |= (.data += [{_id: "InvaderCode", user: "2", branch: "default", activeWorld: true, modules: {main: "module.exports.loop = function(){};"}, meta: {revision: 0, created: 0, version: 0}, "$loki": (.maxId + 1)}] | .maxId += 1)' \
                "$DATA/db.json" > "$DATA/db.json.tmp"
              mv -f "$DATA/db.json.tmp" "$DATA/db.json"
            fi
            # greenworks.initAPI() runs before anything else and requires
            # steam_appid.txt in the launch cwd when Steam isn't running.
            [ -f "$DATA/steam_appid.txt" ] || echo "464350" > "$DATA/steam_appid.txt"

            ${pkgs.gnused}/bin/sed "s|^steam_api_key =.*|steam_api_key = $STEAM_API_KEY|" \
              ${./server/screepsrc} > "$DATA/.screepsrc"

            echo "screeps private server: http://127.0.0.1:21025 (cli on 127.0.0.1:21026)"
            echo "data dir: $DATA"
            cd "$DATA"
            export SteamAppId=464350
            export SteamGameId=464350
            # Mods live in the nix store, but require() the server's own
            # @screeps/* packages. Plain node (unlike NW.js) honors NODE_PATH,
            # and the launcher passes its env to every child process.
            export NODE_PATH="$STEAM_SCREEPS/package/node_modules"
            # Headless launch, same pattern as NixOS-Configuration's steamcmd
            # game servers: skip the NW.js GUI (screeps_server) and run the
            # backend directly. The Steam bundle ships a plain node
            # (resources/node) exactly for this: the launcher CLI's `start`
            # reads ./.screepsrc from cwd and spawns storage/backend/engine
            # children via process.execPath.
            exec ${screepsServerRun}/bin/steam-run "$STEAM_SCREEPS/resources/node" \
              "$STEAM_SCREEPS/package/node_modules/@screeps/launcher/bin/screeps.js" start "$@"
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

        # Wipe the private-server world. The data dir regenerates from the
        # seed database on the next `nix run .#server`.
        reset-local = {
          type = "app";
          program = toString (pkgs.writeShellScript "reset-local" ''
            set -euo pipefail
            DATA="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
            ${pkgs.procps}/bin/pkill -f 'screeps.js start' 2>/dev/null || true
            rm -rf "$DATA"
            echo "world reset: $DATA removed (fresh world on next nix run .#server)"
          '');
        };

        # Connect to the private server's CLI (port 21026). Use it to manage
        # the running server, e.g. setPassword('YourUsername', 'password').
        cli = {
          type = "app";
          program = toString (pkgs.writeShellScript "screeps-cli" ''
            set -euo pipefail
            STEAM_SCREEPS="''${STEAM_SCREEPS_DIR:-$HOME/.local/share/Steam/steamapps/common/Screeps/server}"
            exec ${screepsServerRun}/bin/steam-run "$STEAM_SCREEPS/resources/node" \
              "$STEAM_SCREEPS/package/node_modules/@screeps/launcher/bin/screeps.js" cli "$@"
          '');
        };

        # Push main.js to the private server (default http://127.0.0.1:21025),
        # self-provisioning: if signin fails it sets the account password via
        # the server CLI and retries; after deploy it auto-places Spawn1 if
        # the account owns nothing. Only account creation itself is manual
        # (once per world, in the Steam client — binds your Steam identity).
        # Credentials come from env vars, or from age-encrypted
        # secrets/SCREEPS_LOCAL_CREDS containing one line "username:password":
        #   secrix create secrets/SCREEPS_LOCAL_CREDS -i ~/.ssh/gitlab -r "$(cat ~/.ssh/gitlab.pub)"
        deploy-local = {
          type = "app";
          program = toString (pkgs.writeShellScript "deploy-local" ''
            set -euo pipefail
            URL="''${SCREEPS_LOCAL_URL:-http://127.0.0.1:21025}"
            IDENTITY="''${SCREEPS_IDENTITY:-$HOME/.ssh/gitlab}"

            if { [ -z "''${SCREEPS_LOCAL_EMAIL:-}" ] || [ -z "''${SCREEPS_LOCAL_PASSWORD:-}" ]; } \
               && [ -f secrets/SCREEPS_LOCAL_CREDS ]; then
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
            # Get the room id first: place-spawn demands a room that exists in
            # db.rooms AND contains an unowned controller (the server's own
            # world-start-room falls back to hardcoded W5N5, a controller-less
            # center room — useless). No HTTP endpoint distinguishes "unowned
            # controller" from "no controller", so read candidates from the
            # world db and try them in order.
            STATUS=$($CURL -sS -H "X-Token: $TOKEN" "$URL/api/user/world-status" \
              | $JQ -r '.status // empty')
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

        secrix = secrix.secrix self;
      };
    };
}
