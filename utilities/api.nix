{ pkgs, server ? "http://127.0.0.1:21025", tokenFile ? ".token" }:

pkgs.writeShellScriptBin "api.sh" ''
  set -euo pipefail

  SERVER="''${SCREEPS_SERVER:-${server}}"
  TOKEN_FILE="''${SCREEPS_TOKEN_FILE:-${tokenFile}}"
  API_PATH="''${1:?usage: api.sh /api/... [curl args...]}"
  shift

  TOKEN=$(cat "$TOKEN_FILE")
  HEADERS=$(mktemp)

  ${pkgs.curl}/bin/curl --silent --dump-header "$HEADERS" \
    --header "X-Token: $TOKEN" --header "X-Username: $TOKEN" \
    "$SERVER$API_PATH" "$@"

  NEW=$(${pkgs.gawk}/bin/awk 'tolower($1) == "x-token:" {print $2}' "$HEADERS" | tr -d '\r')
  if [ -n "$NEW" ]; then
    printf '%s' "$NEW" > "$TOKEN_FILE"
  fi
  rm -f "$HEADERS"
''
