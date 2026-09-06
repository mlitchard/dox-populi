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
  };

  outputs = { self, nixpkgs, paradox, typed-screeps, secrix, disko, gitlab-ci, determinate }:
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
      # Atlas lives in the paradox *source* (the flake input), not the
      # installed package output.
      atlas = "${paradox}/lib/dox";

      # secrix CLI as a devShell command (llm-core pattern: tool packages
      # included in devShell packages, not reached via `nix run`).
      secrixApp = secrix.secrix self;
      secrixCli = pkgs.writeShellApplication {
        name = "secrix";
        text = ''
          exec ${secrixApp.program} "$@"
        '';
      };

      build = pkgs.callPackage ./build.nix {
        inherit paradoxBin atlas typed-screeps;
      };

      server = pkgs.callPackage ./server.nix {
        inherit secrixCli;
        inherit (build) mainPayload tutorialPayload;
      };

      viewer = pkgs.callPackage ./viewer.nix {
        inherit (server) serverNode;
      };

      vm = pkgs.callPackage ./vm/image.nix {
        inherit self system nixpkgs disko determinate flakeInputSources;
      };
    in
    {
      nixosConfigurations = vm.nixosConfigurations;

      packages.${system} = {
        inherit (build) generated main;
        secrix = secrixCli;
        default = build.main;
        # Exported so CI builds them outside the app path.
        screeps-server = server.screepsServer;
        screeps-viewer = viewer.screepsViewer;
        inherit (vm) vm-image vm-image-zst installer-iso;
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
          echo "  nix run .#server              — run the private Screeps server (nix-vendored — no purchase needed)"
          echo "  nix run .#deploy-local        — push main.js (or -- tutorial-js) to the private server"
          echo "  nix run .#client              — browser viewer on :8080 (open-source renderer, no purchase)"
          echo "  nix run .#cli                 — connect to the private server CLI (21026)"
          echo "  nix run .#stop                — stop the server (world kept)"
          echo "  nix run .#reset-local         — stop server + wipe the private world"
          echo "  nix run .#lock-mods           — re-pin server/mods (after editing its package.json)"
          echo "  nix run .#deploy              — bundle and push main.js to screeps.com (optional)"
          echo "  nix run .#gitlab-ci > .gitlab-ci.yml — regenerate the CI config"
          echo "  nix run .#installer           — provision the dev VM disk (one-time dd install)"
          echo "  nix run .#gen-run-vm          — regenerate run-vm.sh after hardware changes"
          echo "  ./run-vm.sh                   — run the installed dev VM"
          echo "  nix flake check               — run all checks"
        '';
      };

      checks.${system} = build.checks // viewer.checks // vm.checks // {
        build = build.main;
      };

      gitlab = import ./ci.nix;

      apps.${system} = build.apps // server.apps // viewer.apps // vm.apps // {
        # Regenerate CI config: nix run .#gitlab-ci > .gitlab-ci.yml
        gitlab-ci = gitlab-ci.apps.${system}.gitlab-ci;

        secrix = secrix.secrix self;
      };
    };
}
