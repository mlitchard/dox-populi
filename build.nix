{ pkgs, paradoxBin, atlas, typed-screeps }:

let
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

  # Assemble the full TS project (harness + generated + vendored types).
  tsSrc = pkgs.runCommand "dox-populi-ts-src" { } ''
    mkdir -p $out/vendor
    cp -r ${./harness} $out/harness
    cp -r ${generated} $out/generated
    cp ${typed-screeps}/dist/index.d.ts $out/vendor/screeps.d.ts
    cp ${./tsconfig.json} $out/tsconfig.json
  '';

  main = pkgs.stdenv.mkDerivation {
    name = "dox-populi-main";
    src = tsSrc;
    nativeBuildInputs = [ pkgs.esbuild pkgs.typescript ];
    buildPhase = ''
      tsc --noEmit -p tsconfig.json
      esbuild harness/main.ts --bundle --format=cjs --platform=node \
        --external:role.harvester --outfile=main.js
      esbuild harness/role.harvester.ts --bundle --format=cjs --platform=node \
        --outfile=role.harvester.js
    '';
    installPhase = ''
      mkdir -p $out
      cp main.js role.harvester.js $out/
    '';
  };

  # JSON payloads for the server's /api/user/code endpoint, built ahead
  # of time so deploy-local only signs in and posts one file.
  mainPayload = pkgs.runCommand "main-js-payload.json" { } ''
    ${pkgs.jq}/bin/jq -n --rawfile main ${main}/main.js \
      --rawfile harvester ${main}/role.harvester.js \
      '{branch: "default", modules: {main: $main, "role.harvester": $harvester}}' > $out
  '';
  tutorialPayload = pkgs.writeText "tutorial-js-payload.json" (builtins.toJSON {
    branch = "default";
    modules = pkgs.lib.mapAttrs'
      (name: _: {
        name = pkgs.lib.removeSuffix ".js" name;
        value = builtins.readFile (./tutorial-js/section1 + "/${name}");
      })
      (pkgs.lib.filterAttrs
        (name: type: type == "regular" && pkgs.lib.hasSuffix ".js" name)
        (builtins.readDir ./tutorial-js/section1));
  });
in
{
  inherit generated tsSrc main mainPayload tutorialPayload;

  apps = {
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
        IDENTITY="''${SCREEPS_IDENTITY:-$HOME/.ssh/gitlab}"
        TOKEN=$(${pkgs.age}/bin/age -d -i "$IDENTITY" secrets/SCREEPS_TOKEN)
        ${pkgs.jq}/bin/jq -n --rawfile main ${main}/main.js \
          --rawfile harvester ${main}/role.harvester.js \
          '{branch: "default", modules: {main: $main, "role.harvester": $harvester}}' \
        | ${pkgs.curl}/bin/curl --fail-with-body -X POST \
            "https://screeps.com/api/user/code" \
            -H "X-Token: $TOKEN" \
            -H "Content-Type: application/json" \
            --data @-
        echo
        echo "deployed main.js to branch 'default'"
      '');
    };
  };

  checks = {
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
  };
}
