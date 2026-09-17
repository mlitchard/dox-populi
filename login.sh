#!/usr/bin/env bash
set -euo pipefail

SERVER="${SCREEPS_SERVER:-http://127.0.0.1:21025}"
EMAIL="${1:?usage: login.sh <user> <pass>}"
PASSWORD="${2:?usage: login.sh <user> <pass>}"

# The response body arrives first; --write-out adds the HTTP status
# code on its own line after it.
RESPONSE=$(curl --silent \
  --request POST "$SERVER/api/auth/signin" \
  --header 'Content-Type: application/json' \
  --data "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  --write-out $'\n%{http_code}')

CODE=${RESPONSE##*$'\n'}
BODY=${RESPONSE%$'\n'*}

echo "$BODY" >&2
echo "HTTP $CODE" >&2

if [ "$CODE" != 200 ]; then
  exit 1
fi

printf '%s' "$BODY" | jq -r .token
