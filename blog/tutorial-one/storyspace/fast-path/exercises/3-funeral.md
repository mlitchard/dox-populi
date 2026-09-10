# The 1500-Tick Funeral

Every creep dies of old age. `CREEP_LIFE_TIME` in the engine's
constants is 1500 ticks, and the panel counts it down: click your
harvester and watch `ticks to live`.

The original tutorial's `main.js` runs the harvester role on every
creep it finds. Read it and `role.harvester.js`, then answer on paper
before you run anything: what happens at tick 1500, and what does the
room look like at tick 1600?

1. Deploy the original tutorial — `nix run .#deploy-local --
   tutorial-js` — and start its creep:

   ```js
   Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester1')
   ```

2. Waiting out 1500 ticks in real time is optional. The tick length is
   a flake default in `server.nix`; restart the server with
   `SCREEPS_TICK_MS=100 nix run .#server` and the funeral arrives ten
   times sooner. The world state survives the restart.
3. Click the creep and watch `ticks to live` run down to zero. Hold
   the room at tick 1600 against your paper.
4. Deploy the port — `nix run .#deploy-local` — and watch the same
   room. Find the lines in `harness/main.ts` that account for the
   difference.
5. Stay for a second funeral. Write down what happens when this
   creep's `ticks to live` reaches zero, then watch it happen.

## Questions worth a minute

- Which lines of which file decided what the room looks like at tick
  1600?
- What does the spawn's energy read after each funeral, and what
  spent it?
- `Memory.trace` kept records through both funerals in the dox world.
  Whose, and what does each record end with?
