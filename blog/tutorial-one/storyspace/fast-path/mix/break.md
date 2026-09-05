# Move Fast and Break Things

The deploy pipeline has two gates. This challenge trips both on
purpose. Write down your prediction before each run — the point is
comparing what you expected the checker to say against what it said.

## Break the spec

1. Open `dox/creeps.dox`. Remove `work` from the `BodyPart` union.
   `harvesterBody` still uses it.
2. Write down what you think `paradox check --path dox` will say.
3. Run it. Compare the rejection to your prediction.
4. Put `work` back and run the check again.

## Break the harness

1. Open `harness/main.ts`. Change the comparison `role === "harvester"`
   to a role the spec does not declare — `"miner"` will do.
2. Write down what you think the build will say.
3. Run `nix run .#deploy-local`. tsc runs inside the build and rejects
   the comparison; nothing ships.
4. Restore `"harvester"` and deploy again. The bundle lands.

## Stretch Goal

Make a change the checkers accept, and watch it land in the world.

1. In `dox/creeps.dox`, add a second `work` to `harvesterBody`.
2. Run `nix run .#deploy-local`. Both gates pass.
3. The running harvester still has the old body. Retire it from the
   console tab:

   ```js
   Object.values(Game.creeps)[0].suicide()
   ```

   The harness spawns a replacement with the new body. It costs
   exactly the 300 energy the spawn holds.
4. Watch the new harvester at the source. Two `work` parts harvest
   twice as much per tick, so it fills in half the time and the
   delivery trips come faster.
