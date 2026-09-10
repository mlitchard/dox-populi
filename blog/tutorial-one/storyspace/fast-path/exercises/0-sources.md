# Picking a Source

Your room has two sources. Both programs send the harvester to one of
them, and each picks differently.

[role.harvester.js](https://raw.githubusercontent.com/screeps/tutorial-scripts/refs/heads/master/section1/role.harvester.js):

```js
var sources = creep.room.find(FIND_SOURCES);
if(creep.harvest(sources[0]) == ERR_NOT_IN_RANGE) {
    creep.moveTo(sources[0]);
}
```

[harness/main.ts]()https://gitlab.com/dox-populi/screeps/-/raw/tutorial-one/harness/main.ts):

```ts
const source = creep.pos.findClosestByPath(FIND_SOURCES);
```

The first takes index zero of whatever `find` returns. The second
measures path distance from where the creep stands. This exercise puts
both on screen.

1. Query the room. `room-feed` signs in, opens the same websocket
   feed the viewer reads, and prints the spawn and the source list in
   the server's own order:

   ```
   nix run .#room-feed -- <user> <pass>
   ```

   ```json
   {"room":"W9N9","spawn":{"name":"Spawn1","x":17,"y":40},"sources":[{"id":"…","x":8,"y":41},{"id":"…","x":23,"y":44}]}
   ```

   Index zero of `sources` is where `sources[0]` points.
2. Compute each source's distance from the spawn by hand:

   ```
   d = max(|x2 - x1|, |y2 - y1|)
   ```

   This is the creep's travel time in ticks. A creep steps one tile
   per tick in any of eight directions. Each diagonal step closes one
   tile of both gaps at once, so the smaller gap disappears along the
   way and the trip lasts as long as the larger one. The game's
   `getRangeTo` reports this number.

   For the spawn at (17,40) in the output above:

   ```
   source at (8,41):  max(|8-17|,  |41-40|) = max(9, 1) = 9
   source at (23,44): max(|23-17|, |44-40|) = max(6, 4) = 6
   ```

   The second source in the list is the closer one. Walls and swamps
   can stretch the walked route past this count;
   `findClosestByPath` measures the real route. Now write down your
   prediction: which source does `sources[0]` send the creep to, and
   is it the closer one by your arithmetic?
3. Deploy the original tutorial — `nix run .#deploy-local --
   tutorial-js` — and start its creep from the console tab:

   ```js
   Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester1')
   ```

4. Watch which source it walks to, and check it against your
   prediction and your arithmetic.

5. Try the other layout: press the respawn button, place the spawn
   beside the other source, and repeat steps 1 through 3 — new query,
   new arithmetic, new prediction. Where does the creep go now?

6. Deploy the port — `nix run .#deploy-local` — and watch its
   harvester's route from the spawn you just placed.

## Questions worth a minute

- `sources[0]` chose the same source from both spawn positions. Where
  in the code was that choice made?
- Wipe the world (`.server-data`), start the server again, and re-run
  the query. Compare the source ids and their order against your
  notes. What survived the wipe, and how reliable does that make
  `sources[0]` as a way to pick a source?
- Every run harvested successfully. What did each one cost in
  round-trip time, and which program would you rather tune?
