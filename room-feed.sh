#!/usr/bin/env bash
set -euo pipefail

SERVER="${SCREEPS_SERVER:-http://127.0.0.1:21025}"
EMAIL="${1:-${SCREEPS_EMAIL:-}}"
PASSWORD="${2:-${SCREEPS_PASSWORD:-}}"
LISTEN_SECONDS="${LISTEN_SECONDS:-3}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "usage: room-feed.sh <user> <pass>   (or set SCREEPS_EMAIL / SCREEPS_PASSWORD)" >&2
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
HDRS=$(mktemp)
trap 'rm -f "$HDRS"' EXIT
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
if command -v websocat >/dev/null; then
  WEBSOCAT=(websocat)
else
  WEBSOCAT=(nix run nixpkgs#websocat --)
fi

# The sockjs framed endpoint: each client message goes out JSON-encoded
# as ["..."], and server messages arrive as a[...] lines of strings.
# The auth frame goes first; the sleep lets "auth ok" land before the
# subscribe goes out. The first message on the room channel is the full
# snapshot; jq pulls the spawn and sources out of it.
{
  printf '["auth %s"]\n' "$TOKEN"
  sleep 1
  printf '["subscribe room:%s"]\n' "$ROOM"
  sleep "$LISTEN_SECONDS"
} | "${WEBSOCAT[@]}" "${SERVER/http/ws}/socket/000/$$/websocket" \
  | sed -n 's/^a//p' \
  | jq -cn --arg room "$ROOM" '
      first(inputs[]
        | select(startswith("[")) | fromjson
        | select(type == "array" and .[0] == "room:" + $room)
        | .[1].objects | to_entries)
      | {room: $room,
         spawn: (map(select(.value.type == "spawn")
           | {name: .value.name, x: .value.x, y: .value.y}) | first),
         sources: map(select(.value.type == "source")
           | {id: .key, x: .value.x, y: .value.y})}'
