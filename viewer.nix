{ pkgs, serverNode }:

let
  # Browser viewer built on the ISC-licensed @screeps/renderer (the
  # official open-sourced renderer + images) — watching needs no
  # purchased game files. viewer/src is this repo's TypeScript;
  # `npm run build` bundles it with esbuild and copies the metadata
  # package's images into dist/assets, so the page serves fully
  # offline. Pinned by `nix run .#lock-viewer`.
  screepsViewer = pkgs.buildNpmPackage {
    pname = "dox-populi-viewer";
    version = "0.0.1";
    src = ./viewer;
    nodejs = serverNode;
    npmDepsHash = pkgs.lib.trim (builtins.readFile ./viewer/npm-deps-hash);
    installPhase = ''
      mkdir -p $out
      cp -r dist/. $out/
      cp proxy.mjs $out/
    '';
  };
in
{
  inherit screepsViewer;

  apps = {
    # Browser viewer: one origin for everything. proxy.mjs serves
    # the nix-built page (renderer, images, our bundle) on 8080 and
    # forwards /api and /socket to the game server, so the browser
    # never makes a cross-origin request. Open
    # http://127.0.0.1:8080/ on the host and sign in with your
    # deploy-local credentials.
    client = {
      type = "app";
      program = toString (pkgs.writeShellScript "screeps-viewer" ''
        set -euo pipefail
        export VIEWER_HOST="''${SCREEPS_CLIENT_HOST:-''${SCREEPS_HOST:-127.0.0.1}}"
        export SCREEPS_DATA_DIR="''${SCREEPS_DATA_DIR:-$(${pkgs.git}/bin/git rev-parse --show-toplevel)/.server-data}"
        exec ${serverNode}/bin/node ${screepsViewer}/proxy.mjs
      '');
    };

    # Same pinning flow for the viewer package. Rerun after editing
    # viewer/package.json.
    lock-viewer = {
      type = "app";
      program = toString (pkgs.writeShellScript "lock-viewer" ''
        set -euo pipefail
        cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)/viewer"
        ${serverNode}/bin/npm install --package-lock-only --ignore-scripts --no-audit --no-fund
        ${pkgs.prefetch-npm-deps}/bin/prefetch-npm-deps package-lock.json > npm-deps-hash
        ${pkgs.git}/bin/git add package.json package-lock.json npm-deps-hash
        echo "pinned: viewer/package-lock.json + npm-deps-hash (staged; commit when ready)"
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
  };

  checks = {
    # The viewer's own TypeScript, checked against the ambient
    # declarations it carries (viewer/src/types.d.ts).
    viewer-typecheck = pkgs.runCommand "viewer-typecheck"
      { nativeBuildInputs = [ pkgs.typescript ]; } ''
      cp -r ${./viewer}/. .
      chmod -R u+w .
      tsc --noEmit -p tsconfig.json
      touch $out
    '';
  };
}
