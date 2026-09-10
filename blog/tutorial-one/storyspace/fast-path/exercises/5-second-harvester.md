# The Second Harvester

Growth is where the two programs come apart. This challenge adds a
second creep to each world and watches what the existing decisions do
with it.

## In the JS world

1. Deploy the original tutorial — `nix run .#deploy-local --
   tutorial-js` — and issue both spawn commands from the console tab:

   ```js
   Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester1')
   Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester2')
   ```

   Read what each command answers. Write down what has to happen
   before Harvester2 exists, then watch the spawn's `store.energy`
   in the panel until it does.
2. You've read `role.harvester.js`. Write down where each creep will
   work, then watch. Click each creep and compare their `actions`
   rows against what you wrote.

## In the dox world

3. The port's population is a decision you can read. In
   `harness/main.ts`:

   ```ts
   if (spawn && !spawn.spawning && Object.keys(Game.creeps).length < 1) {
   ```

   One harvester, by policy. Change `< 1` to `< 2` and run
   `nix run .#deploy-local`.
4. Write down when the second harvester will appear and where each
   of the two will work — the source line you found in the first
   exercise answers from each creep's own position. Then watch the
   room and hold it against your notes.
5. Write down what the room settles into, then retire one creep and
   watch what the policy does about it.

## Questions worth a minute

- Growth cost a console command in one world and an edit in the
  other. What exactly did each world ask of you?
- Where did each pair of creeps end up, and which lines put them
  there?
- After step 5's retirement, something rebuilt the dox harvester.
  What would rebuild Harvester2 in the JS world?
