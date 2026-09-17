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
      paradoxBin = paradox.packages.${system}.paradox;
      # Atlas ships in the paradox flake source.
      atlas = "${paradox}/lib/dox";

      secrixApp = secrix.secrix { nixosConfigurations = { }; };
      secrixCli = pkgs.writeShellApplication {
        name = "secrix";
        text = ''
          exec ${secrixApp.program} "$@"
        '';
      };

      # Spec-to-bundle chain: generated TS, the main/invader/raidmod
      # bundles, deploy payload; apps generate/deploy; spec and type checks.
      build = pkgs.callPackage ./build.nix {
        inherit paradoxBin atlas typed-screeps secrixCli;
      };

      # The nix-vendored private server and its mods, with every
      # server-side app (server, cli, deploy-local, stop, reset-local,
      # lock-server, lock-mods).
      server = pkgs.callPackage ./server.nix {
        inherit secrixCli;
        inherit (build) mainPayload invaderMain raidMod;
      };

      # Browser viewer (open-source renderer, no purchased game files);
      # provides apps.client, lock-viewer, and checks.viewer-typecheck.
      viewer = pkgs.callPackage ./viewer.nix { inherit (server) serverNode; };

      # Dev VM: hardware contract, run-vm.sh renderer, the vm/installer
      # systems and disk-image packages, vm-boot and run-vm-fresh checks.
      vm = pkgs.callPackage ./vm/image.nix {
        inherit self system nixpkgs disko determinate flakeInputSources;
      };
    in
    {
      nixosConfigurations = vm.nixosConfigurations;

      packages.${system} = {
        inherit (build) generated main;
        # Exported so CI builds them outside the itest job.
        invader-main = build.invaderMain;
        raid-mod = build.raidMod;
        screeps-server = server.screepsServer;
        screeps-viewer = viewer.screepsViewer;
        secrix = secrixCli;
        default = build.main;
        inherit (vm) vm-image vm-image-zst installer-iso;
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
          echo "  nix run .#client              — browser viewer on :8080 (open-source renderer, no purchase)"
          echo "  nix run .#stop                — stop server + client (world kept)"
          echo "  nix run .#reset-local         — stop server + wipe the private world"
          echo "  nix run .#itest               — VM integration test: deploy + spawn + harvest"
          echo "  nix run .#installer           — provision the dev VM disk (one-time dd install)"
          echo "  nix run .#gen-run-vm          — regenerate run-vm.sh after hardware changes"
          echo "  ./run-vm.sh                   — run the installed dev VM"
          echo "  nix flake check               — run all checks"
        '';
      };

      checks.${system} = build.checks // viewer.checks // vm.checks // {
        # End-to-end VM test: server + deploy + harvest.
        itest = pkgs.callPackage ./tests/integration.nix {
          serverProgram = self.apps.${system}.server.program;
          deployProgram = self.apps.${system}.deploy-local.program;
          inherit (server) tickMs;
          # The dev VM's declared sizing — the test runs on the same
          # hardware contract.
          memorySize = vm.hardware.runMemMiB;
          cores = vm.hardware.runCpus;
        };

        build = build.main;
      };

      gitlab = import ./ci.nix;

      apps.${system} = build.apps // server.apps // viewer.apps // vm.apps // {
        # Build checks.itest with streamed logs.
        itest = {
          type = "app";
          program = toString (pkgs.writeShellScript "itest" ''
            set -euo pipefail
            exec nix build -L --no-link \
              "$(${pkgs.git}/bin/git rev-parse --show-toplevel)#checks.${system}.itest" "$@"
          '');
        };

        # Print the room, spawn, and source list from the server's
        # socket feed: nix run .#room-feed -- <user> <pass>
        room-feed = {
          type = "app";
          program = toString (pkgs.writeShellScript "room-feed" ''
            set -euo pipefail
            export PATH=${pkgs.lib.makeBinPath [ pkgs.curl pkgs.jq pkgs.websocat pkgs.gawk pkgs.coreutils ]}:$PATH

            SERVER="''${SCREEPS_SERVER:-http://127.0.0.1:21025}"
            EMAIL="''${1:-''${SCREEPS_EMAIL:-}}"
            PASSWORD="''${2:-''${SCREEPS_PASSWORD:-}}"

            if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
              echo "usage: nix run .#room-feed -- <user> <pass>   (or set SCREEPS_EMAIL / SCREEPS_PASSWORD)" >&2
              exit 1
            fi

            TOKEN=$(curl -sS -X POST "$SERVER/api/auth/signin" \
              -H 'Content-Type: application/json' \
              --data "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | jq -r .token)
            if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
              echo "signin failed against $SERVER" >&2
              exit 1
            fi

            # Every authenticated response may rotate the token via its X-Token
            # header; the socket auth below needs the current one.
            WORK=$(mktemp -d)
            trap 'rm -rf "$WORK"' EXIT
            HDRS="$WORK/headers"
            adopt_token() {
              local rotated
              rotated=$(tr -d '\r' < "$HDRS" | awk 'tolower($1) == "x-token:" {print $2}')
              if [ -n "$rotated" ]; then TOKEN="$rotated"; fi
            }

            USER_ID=$(curl -sS -D "$HDRS" -H "X-Token: $TOKEN" -H "X-Username: $TOKEN" \
              "$SERVER/api/auth/me" | jq -r ._id)
            adopt_token

            ROOM=$(curl -sS -D "$HDRS" -H "X-Token: $TOKEN" -H "X-Username: $TOKEN" \
              "$SERVER/api/user/rooms?id=$USER_ID" | jq -r '(.rooms // .list)[0]')
            adopt_token
            if [ -z "$ROOM" ] || [ "$ROOM" = "null" ]; then
              echo "no room found for $EMAIL — place a spawn first" >&2
              exit 1
            fi

            # The sockjs framed endpoint: each client message goes out
            # JSON-encoded as ["..."], and server messages arrive as a[...]
            # lines of strings. The fifo feeds websocat's stdin so each
            # outgoing frame is sent in response to a server message: auth
            # first, subscribe once the server answers "auth ok", then read
            # until the room snapshot (the first message on the room channel)
            # arrives and pull the spawn and sources out of it.
            mkfifo "$WORK/in"
            exec 4< <(websocat "''${SERVER/http/ws}/socket/000/$$/websocket" < "$WORK/in")
            exec 3> "$WORK/in"

            printf '["auth %s"]\n' "$TOKEN" >&3

            while IFS= read -r line <&4; do
              case "$line" in a*) ;; *) continue ;; esac
              frame="''${line#a}"
              if printf '%s' "$frame" | jq -e \
                  'any(.[]?; type == "string" and startswith("auth ok"))' >/dev/null; then
                printf '["subscribe room:%s"]\n' "$ROOM" >&3
                continue
              fi
              objects=$(printf '%s' "$frame" | jq -c --arg room "$ROOM" '
                [.[]? | select(type == "string" and startswith("[")) | fromjson
                 | select(type == "array" and .[0] == "room:" + $room)
                 | .[1].objects][0] // empty')
              if [ -n "$objects" ]; then
                printf '%s' "$objects" | jq -c --arg room "$ROOM" '
                  to_entries
                  | {room: $room,
                     spawn: (map(select(.value.type == "spawn")
                       | {name: .value.name, x: .value.x, y: .value.y}) | first),
                     sources: map(select(.value.type == "source")
                       | {id: .key, x: .value.x, y: .value.y})}'
                break
              fi
            done

            exec 3>&- 4<&-
          '');
        };

        secrix = secrixApp;

        # Regenerate CI config: nix run .#gitlab-ci > .gitlab-ci.yml
        gitlab-ci = gitlab-ci.apps.${system}.gitlab-ci;
      };
    };
}
