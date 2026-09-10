# Same Mistake, Two Worlds

One typo, made twice — once in the original tutorial's JavaScript,
once in the spec. Write down your prediction before each run.

## The JS world

1. Deploy the original tutorial and start its creep:
   `nix run .#deploy-local -- tutorial-js`, then from the console tab:

   ```js
   Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester1')
   ```

   Watch the harvest loop run.
2. Open `tutorial-js/section1/role.harvester.js`. Change
   `getFreeCapacity` to `getFreCapacity`.
3. Write down what the deploy will say, and what the creep will do.
4. Deploy again. The console tab and the viewer hold the answers —
   compare them against what you wrote.
5. Restore `getFreeCapacity`.

## The dox world

1. Deploy the port: `nix run .#deploy-local`. The same loop, driven
   by the spec.
2. Open `dox/creeps.dox`. In `harvesterBody`, change `work` to `wrok`.
3. Write down what the deploy will say, and what the creep will do.
4. Run `nix run .#deploy-local` and compare against what you wrote —
   the terminal and the viewer both have something to say.
5. Restore `work` and deploy again.

## Questions worth a minute

- When did each world report the typo, and where did you read the
  report?
- What was running on the server while each report reached you?
- Each report named something. Which one named the mistake?
