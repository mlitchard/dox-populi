# Viewer contract: @screeps/renderer + private-server protocol

Research findings (2026-09-01) the viewer/ implementation is built
against. Sources: github.com/screeps/renderer (engine, metadata, demo),
screepers/node-screeps-api, screepers/python-screeps docs.

## Renderer

- Packages: `@screeps/renderer` 1.6.10 and `@screeps/renderer-metadata`
  1.6.10. License: ISC (LICENSE.txt, Artem Chivchalov / screeps.com).
  Redistribution on the ISO is permitted with the notice kept.
- The published `@screeps/renderer` tarball ships `dist/` only; the
  declared `main.d.ts` is absent from the tarball, and it is stale
  anyway (declares `worldOptions`; the implementation reads
  `worldConfigs`). Trust GameRenderer.js. We carry our own ambient
  declarations in viewer/src/types.d.ts.
- Init sequence (from demo/src/components/Canvas.jsx):
  `GameRenderer.compileMetadata(metadata)` once, then
  `new GameRenderer({ size, resourceMap, worldConfigs, backgroundColor,
  useDefaultLogger })`, then `await init(containerDiv)` (the renderer
  creates its own canvas and appends it), then `await
  setTerrain(terrainArray)`, then `applyState(state, tickSeconds)` per
  tick. `tickDuration` is seconds (demo uses 2.5).
- worldConfigs working values (demo/src/config/worldConfigs.js):
  ATTACK_PENETRATION 10, CELL_SIZE 100, RENDER_SIZE 2048×2048,
  VIEW_BOX 10000, ROOM_SIZE 100, lighting "normal", userOwnerColor,
  userFlagColor, metadata = the metadata package's default export,
  BADGE_URL pointed at the server's
  `/api/user/badge-svg?username=%1`, and `gameData.player` = the
  signed-in user's `_id` (drives own-color rendering).
- `applyState` wants a FULL snapshot every tick: `state.objects` is an
  ARRAY of `{_id, type, room, x, y, ...}`; objects missing from the
  array are removed from the scene. `state.users` is a map
  `userId → {_id, username, badge}`; `state.gameTime`, `info`,
  `visual` accompany it. The viewer accumulates the world itself and
  hands over a fresh array each tick.
- Terrain: `setTerrain(array)` takes `{x, y, type}` tiles, type `wall`
  or `swamp`, plain tiles omitted — exactly the unencoded
  `/api/game/room-terrain` response.
- Assets: the images live in `@screeps/renderer-metadata/images/`
  (svg + png). The alias→file mapping is NOT in the metadata package —
  it lives in the renderer repo's demo (resourceMap.js) and is
  vendored at viewer/src/resourceMap.ts with values rewritten to
  `assets/<file>`. The build copies the images directory to
  `dist/assets/`, so the page serves fully offline. The metadata's
  `objects` key set is the supported `type` vocabulary; unknown types
  log "Unsupported object type".

## Server protocol (private server; no shards)

- Auth: `POST /api/auth/signin {email,password}` → `{token}`. Every
  request sends the current token as BOTH `X-Token` and `X-Username`;
  every response may rotate it via the `X-Token` response header —
  hold one mutable token cell.
- Socket: `ws://host:port/socket/websocket` (plain WebSocket). On
  open send `auth <token>`; reply is the text frame
  `auth ok <newToken>` (rotates the token again). Subscribe with
  `subscribe room:<name>` (no shard segment on private servers).
- Frames: JSON arrays `[channel, payload]` for channel messages;
  space-separated text for control frames (`auth`, `protocol <n>`,
  `time <ms>`, `package <n>`); any frame may arrive as
  `gz:<base64 zlib>` (we never send `gzip on`, and inflate defensively
  with DecompressionStream("deflate") if one appears).
- Room feed: first message per subscription is a full snapshot
  (`objects` keyed by `_id`; `gameTime` undefined on this first
  message); every later message is a diff — changed fields only, `_id
  → null` means the object left the room. Array-valued fields (creep
  `body`) can be diffed as index-keyed objects; the merge must handle
  an object-diff landing on an array.
- The room feed carries NO users map. Seed objects+users in one shot
  from `GET /api/game/room-objects?room=<r>` (array-shaped objects
  plus `users`), then resolve new user ids from later diffs via
  `GET /api/user/find?id=<id>`.
- Terrain REST: unencoded `/api/game/room-terrain?room=<r>` feeds
  `setTerrain` directly; rare private-server worlds answer with the
  encoded form regardless (a digit string; 0 plain, 1/3 wall,
  2 swamp) — sniff and expand.
- Room discovery: `GET /api/auth/me` → `_id`;
  `GET /api/user/rooms?id=<id>` returns a flat `rooms` (or `list`)
  array on private servers (no `shards` key);
  `GET /api/user/world-start-room` as fallback.
