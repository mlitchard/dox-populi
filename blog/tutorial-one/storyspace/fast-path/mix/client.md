# Get in the mix.

The viewer is part of this repo: plain TypeScript and one HTML page in
`viewer/src/`, bundled by esbuild. This challenge adds a creep counter
to the top bar.

1. Open `viewer/src/index.html` and find the `#topbar` line. Add a
   span for the count.
2. Open `viewer/src/main.ts` and find the `onChannel` handler — the
   block that runs once per tick when a room frame arrives. Look at
   how it already updates `#gametime`.
3. Look at `viewer/src/state.ts` to see how `RoomState` holds the
   room's objects, and count the ones whose `type` is `"creep"`.
4. Set your span's text from that count in the tick block.
5. Run `nix flake check` — the viewer has its own tsc gate
   (`viewer-typecheck`) that rejects type errors.
6. Run `nix run .#client`, reload the page, and watch the count move
   when a creep spawns or dies.

# Stretch Goal

Add the spawn's energy next to the count, updated the same way. The
spawn is in the room's objects with `type` `"spawn"`; its energy is in
its `store`. Watching it drain by 300 when a creep is built tells you
where the body budget went.
