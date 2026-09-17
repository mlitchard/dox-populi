# Room snapshot reader for the private server's socket feed.
{ pkgs }:

{
  apps = {
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
  };
}
