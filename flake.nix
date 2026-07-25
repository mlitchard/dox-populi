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
      pkgs = import nixpkgs { inherit system; };
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
    in
    {
      # Required by `secrix.secrix self`; secrets themselves are created
      # against the keys configured in the ~/nixos flake.
      nixosConfigurations = { };

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
          pkgs.age
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
            TOKEN=$(${pkgs.age}/bin/age -d -i "$HOME/.ssh/gitlab" secrets/SCREEPS_TOKEN)
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

        secrix = secrix.secrix self;
      };
    };
}
