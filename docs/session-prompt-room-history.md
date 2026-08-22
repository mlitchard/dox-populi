# Session prompt: room-history recording + replay (screepsmod-history)

## Problem

The world keeps no time series. `Memory.stats` (shell/main.ts) is a
per-tick snapshot, overwritten every tick; the only survivors are two
cumulative counters (births/deaths). When a creep stalls mid-life (the
observed bug: creeps go idle until they die of old age, replacements
work fine), there is no record of what the world looked like when it
happened — no way to scrub back and watch it.

Wanted: a continuous recording of room state, written to files, that
can be fed into a player and replayed like game film.

## Plan

Vendor **`screepsmod-history`** (ScreepsMods org, npm) into the private
server. It snapshots every active room each tick into room-history JSON
chunk files — the exact format the Screeps client's replay/history
player consumes. Recording is server-side ops: zero spec changes, zero
shell changes.

- Record: mod writes ~8KB/tick/room into the server data dir
  (`.server-data/`), continuously.
- Playback: the browser client (`nix run .#client`) gains the history
  scrubber — pick room, pick tick, watch the replay.
- The chunk files are plain JSON — also consumable by external tooling
  (Screeps3D reads the same format) later if wanted.

### Changes

1. **`server/mods/package.json`**: add `screepsmod-history` (same
   pattern as `screepsmod-auth`).
2. **`nix run .#lock-mods`**: re-pin `package-lock.json` +
   `npm-deps-hash`. MANDATORY after the package.json edit — nothing
   else may run npm's resolver (CLAUDE.md law).
3. **Retention config**: the mod defaults to keeping ~200,000 ticks
   (~20MB per active room). Constant disk is a requirement, not a
   nice-to-have: find the mod's retention knob (README /
   `config.history` hooks) and pin a bounded window. Follow the house
   config pattern — default as a `let` binding in `flake.nix` if the
   knob is wired through our server app, env var only as OPTIONAL
   override. NEVER require an env var for correct behavior.
4. **Server restart** to load the mod; confirm chunk files appear under
   `.server-data/` and note WHERE (document the path in the flake app's
   help text or a comment).
5. **Client verification**: open `nix run .#client` on :8080 and
   confirm the history/replay view works against the private server's
   history endpoint. The steamless client bridges to the official
   client assets — check that the history route
   (`/room-history/...`) is proxied; if it 404s, that is a
   client-bridge issue, not a mod issue — diagnose, don't shotgun.

### Open questions (settle in-session, before writing code)

- Mod age: `screepsmod-history` last published ~4 years ago (v1.6.0).
  Verify it loads against our nix-vendored server version — check its
  peer expectations against `server/npm` first. If it fights the
  server, STOP and report; do not fork/patch it in this session
  without the user signing off.
- Storage backend: the mod has an AWS mode (explicitly not
  recommended upstream) and a local-fs mode. Local fs only.
- Does history recording measurably slow the tick loop at our tick
  rate (`tickMs` in flake.nix)? Eyeball tick timing before/after in
  the server log; report the delta.
- Retention knob semantics: ticks vs chunks vs bytes — read the mod
  source on GitHub (NOT /nix/store) and document what the number
  actually bounds.

### Constraints

- nix-pipeline agent territory: `server/mods/package.json`,
  `flake.nix` wiring, maybe docs. No brain (`dox/`), no shell
  (`shell/`) changes — recording is ops, not policy.
- NEVER read `/nix/store/...` paths — consult the mod's GitHub/npm
  page for source.
- After the package.json edit, `nix run .#lock-mods` is the ONLY
  legal re-pin route.
- Cheap checks freely; server restart is fine (world kept);
  `nix run .#reset-local` wipes the world — explicit user request
  only. `.#itest` / `nix flake check` — ask first.
- Complementary, not redundant: `Memory.trace` (the in-shell flight
  recorder: per-creep event/fsm/action/return-code ring buffer) may
  already be in the tree on this branch. History replay shows WHAT
  happened on the field; the trace shows WHY the brain chose it.
  Don't remove one in favor of the other.

### Result

- `nix run .#server` — world is being recorded to bounded-size history
  files, zero setup.
- `nix run .#client` — scrub back through any room's last N ticks and
  watch the game film (e.g. catch a creep at the exact tick it
  stalls, see the room state around it).
- History files on disk, feedable to external players/tooling.

## Files

`server/mods/package.json` (+ its lock/hash via `lock-mods`),
`flake.nix` (retention knob wiring, if needed), this doc. Nothing else.
