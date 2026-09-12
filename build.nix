{ pkgs, paradoxBin, atlas, typed-screeps, secrixCli }:

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
        --external:machine --external:role.harvester --external:role.upgrader \
        --external:role.builder --external:role.defender --outfile=main.js
      esbuild harness/machine.ts --bundle --format=cjs --platform=node \
        --outfile=machine.js
      for role in harvester upgrader builder defender; do
        esbuild harness/role.$role.ts --bundle --format=cjs --platform=node \
          --external:machine --outfile=role.$role.js
      done
    '';
    installPhase = ''
      mkdir -p $out
      cp main.js machine.js role.*.js $out/
    '';
  };
  # JSON payload for the server's /api/user/code endpoint, built ahead
  # of time so deploy-local only signs in and posts one file.
  mainPayload = pkgs.runCommand "main-js-payload.json" { } ''
    ${pkgs.jq}/bin/jq -n --rawfile main ${main}/main.js \
      --rawfile machine ${main}/machine.js \
      --rawfile harvester ${main}/role.harvester.js \
      --rawfile upgrader ${main}/role.upgrader.js \
      --rawfile builder ${main}/role.builder.js \
      --rawfile defender ${main}/role.defender.js \
      '{branch: "default", modules: {main: $main, machine: $machine,
        "role.harvester": $harvester, "role.upgrader": $upgrader,
        "role.builder": $builder, "role.defender": $defender}}' > $out
  '';

  # Raider brain (dox/invader spec + harness/invader.ts); apps.server
  # seeds it as the "raiders" NPC user's users.code.
  invaderMain = pkgs.stdenv.mkDerivation {
    name = "dox-populi-invader-main";
    src = tsSrc;
    nativeBuildInputs = [ pkgs.esbuild ];
    buildPhase = ''
      esbuild harness/invader.ts --bundle --format=cjs --platform=node \
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
      esbuild harness/raidmod.ts --bundle --format=cjs --platform=node \
        --outfile=raidmod.js
    '';
    installPhase = ''
      mkdir -p $out
      cp raidmod.js $out/
    '';
  };
in
{
  inherit generated tsSrc main mainPayload invaderMain raidMod;

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
        IDENTITY="''${SCREEPS_IDENTITY:-''${WORKDIR:-''${HOME:-/root}/work}/identity}"
        if [ ! -f "$IDENTITY" ]; then
          echo "error: no identity key at $IDENTITY (needed to decrypt secrets/SCREEPS_TOKEN)" >&2
          echo "place YOUR key there, or set SCREEPS_IDENTITY=/path/to/your/key" >&2
          exit 1
        fi
        TOKEN=$(${secrixCli}/bin/secrix decrypt secrets/SCREEPS_TOKEN -i "$IDENTITY")
        ${pkgs.jq}/bin/jq -n --rawfile main ${main}/main.js \
          --rawfile machine ${main}/machine.js \
          --rawfile harvester ${main}/role.harvester.js \
          --rawfile upgrader ${main}/role.upgrader.js \
          --rawfile builder ${main}/role.builder.js \
          --rawfile defender ${main}/role.defender.js \
          '{branch: "default", modules: {main: $main, machine: $machine,
            "role.harvester": $harvester, "role.upgrader": $upgrader,
            "role.builder": $builder, "role.defender": $defender}}' \
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
  };
}
