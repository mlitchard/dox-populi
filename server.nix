{ pkgs, secrixCli, mainPayload, tutorialPayload }:

let
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
  inherit serverNode screepsServer serverMods;

  apps = {
    # Run the private Screeps server headless from the nix-vendored
    # launcher. World state lives in .server-data/ at the repo root.
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

        # Env override first, then secrix. The server runs fine with
        # no Steam Web API key at all: screepsmod-auth handles
        # password signin, so readers need nothing from Steam.
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
          # The backend demands a key: empty means it hunts for the
          # Steam client's greenworks library and crash-loops. Any
          # non-empty value disables that path; password signin via
          # screepsmod-auth is what actually authenticates users.
          STEAM_API_KEY="dox-populi-no-steam"
          echo "note: no Steam Web API key; using a dummy (password signin via screepsmod-auth)" >&2
        fi

        mkdir -p "$DATA/logs"
        [ -e "$DATA/assets" ]       || ln -s "$LAUNCHER/init_dist/assets" "$DATA/assets"
        [ -e "$DATA/node_modules" ] || ln -s "$LAUNCHER/init_dist/node_modules" "$DATA/node_modules"
        # mods.json is regenerated every launch: the versioned
        # template plus the nix-vendored mods' entry paths. The cors
        # mod lets the browser viewer on :8080 reach this server's
        # API across origins.
        ${pkgs.jq}/bin/jq --arg auth "${serverMods}/node_modules/screepsmod-auth/index.js" \
          --arg cors "${serverMods}/node_modules/screepsmod-cors/index.js" \
          '.mods += [$auth, $cors]' ${./server/mods.json} > "$DATA/mods.json.tmp"
        mv -f "$DATA/mods.json.tmp" "$DATA/mods.json"
        # Seed the world database on first run (screeps init's job).
        # -s: also replace a 0-byte stub left by a failed GUI launch.
        if [ ! -s "$DATA/db.json" ]; then
          cp "$LAUNCHER/init_dist/db.json" "$DATA/db.json"
          chmod u+w "$DATA/db.json"
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

    cli = {
      type = "app";
      program = toString (pkgs.writeShellScript "screeps-cli" ''
        set -euo pipefail
        exec ${serverNode}/bin/node \
          "${screepsServer}/node_modules/@screeps/launcher/bin/screeps.js" cli "$@"
      '');
    };

    # Push game code to the private server (default http://127.0.0.1:21025):
    # the built main.js, or with argument "tutorial-js" every .js file in
    # tutorial-js/section1 as its own module. Self-provisioning: if signin
    # fails it registers the account via
    # screepsmod-auth and retries. Spawn placement is the player's
    # act, in the viewer. Credentials come from env vars, or from
    # age-encrypted secrets/SCREEPS_LOCAL_CREDS containing one line
    # "username:password":
    #   secrix create secrets/SCREEPS_LOCAL_CREDS -i <your-key> -r "$(cat <your-key>.pub)"
    deploy-local = {
      type = "app";
      program = toString (pkgs.writeShellScript "deploy-local" ''
        set -euo pipefail
        SRC="''${1:-main.js}"
        case "$SRC" in
          main.js)     PAYLOAD=${mainPayload} ;;
          tutorial-js) PAYLOAD=${tutorialPayload} ;;
          *) echo "usage: nix run .#deploy-local -- [main.js|tutorial-js]" >&2
             exit 1 ;;
        esac
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
          echo "(server running? screepsmod-auth loaded?)" >&2
          exit 1
        fi

        $CURL --fail-with-body -sS -X POST "$URL/api/user/code" \
            -H "X-Token: $TOKEN" -H "Content-Type: application/json" \
            --data @"$PAYLOAD"
        echo
        echo "deployed $SRC to $URL (branch 'default')"
      '');
    };

    # Stop the private server (the launcher and its children all
    # carry the vendored server's store path in argv). World data is
    # left intact.
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
  };
}
