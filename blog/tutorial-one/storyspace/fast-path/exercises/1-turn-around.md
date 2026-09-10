# Turn-Around Threshold

The harvester turns for home on one condition. In the original
tutorial it is this line of `role.harvester.js`:

```js
if(creep.store.getFreeCapacity() > 0) {
```

The creep keeps harvesting while any free space remains, so it turns
around completely full. Find the same condition in the port — it is in
`harness/main.ts`, in the harvester branch. The spec holds the role
and the body; this threshold sits in the harness in both worlds.

This challenge changes the threshold and measures the change on
screen.

1. In `harness/main.ts`, change the condition to turn around at
   half-full:

   ```ts
   if (creep.store.getFreeCapacity() > creep.store.getCapacity() / 2) {
   ```

2. Work out the check by hand before you deploy: what you will watch
   in the viewer, and what you expect to see while the colony is
   behaving correctly.

3. Run `nix run .#deploy-local`. Both gates pass. The threshold is a
   number, and a different number is still well-typed.

4. Turn your expectation into a probe — one console line that prints
   whatever your check watches, for example:

   ```js
   JSON.stringify(Memory.trace)
   ```

   Run it a few ticks apart. The objects and fields at your disposal
   are in the [Screeps API reference](https://docs.screeps.com/api/).

5. Run your check against both thresholds, with the panel or your
   probe. If your check wants the spawn spending energy, retire the
   creep — `Object.values(Game.creeps)[0].suicide()` — and the
   harness rebuilds it for 300, leaving the spawn empty. Then restore
   the old condition, deploy, and run the same check against the old
   behavior.

## Where tests come from

Every gate passed, and the colony's rhythm changed anyway. Paradox
verified the spec's named properties. tsc checked types, and the
edited line still compares numbers and yields a boolean — the value
of the threshold sits outside the type system's view. The threshold's
effect on the world was covered by exactly one test: the one you
worked out in step 2 and ran in step 5.

This repo carries its automated form. `tests/integration.nix`
deploys, spawns, and checks the harvest loop by reading
`Memory.trace` latches — a machine reading the same world you watched
in the panel. Open it and find your test in it: what you watched is a
latch, what you expected is an assertion.
