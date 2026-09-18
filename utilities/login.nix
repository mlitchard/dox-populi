{ pkgs, server ? "http://127.0.0.1:21025", tokenFile ? ".token" }:

pkgs.writeShellScriptBin "login.sh" ''
  set -euo pipefail

  SERVER="''${SCREEPS_SERVER:-${server}}"
  TOKEN_FILE="''${SCREEPS_TOKEN_FILE:-${tokenFile}}"
  EMAIL="''${1:?usage: login.sh <user> <pass>}"
  PASSWORD="''${2:?usage: login.sh <user> <pass>}"

  RESPONSE=$(${pkgs.curl}/bin/curl --silent \
    --request POST "$SERVER/api/auth/signin" \
    --header 'Content-Type: application/json' \
    --data "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
    --write-out $'\n%{http_code}')

  CODE=''${RESPONSE##*$'\n'}
  BODY=''${RESPONSE%$'\n'*}

  echo "$BODY" >&2
  echo "HTTP $CODE" >&2

  if [ "$CODE" != 200 ]; then
    exit 1
  fi

  printf '%s' "$BODY" | ${pkgs.jq}/bin/jq -j .token > "$TOKEN_FILE"
  echo "token written to $TOKEN_FILE" >&2
''
