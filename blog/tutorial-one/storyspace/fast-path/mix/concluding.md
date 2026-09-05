# Get in the Mix

By now you've had a bit of time to explore the structure of the dox-populi.
The final two exercises are about the original tutorial and the port in this repo,
and dealing with klanker slop.

Ask the agent in your dev shell at every step — it has read everything
on this disk. Its answer is a claim; the file or the running game is
the evidence; you decide.

## The Original, and the Dox.

git restore the changes you made in the last exercise.

0. Shutdown the server and delete the world, found in .server-data.

1. Start the game with one term each for the server,client and deploy. Find the two
   files that hold the program: dox/creeps.dox and harness/main.ts.
   The original tutorial's JS is in the repo too: tutorial-js/section1.

2. Read tutorial-js/section1 (main.js and role.harvester.js). Before
   running it, write down what the creeps will do and how long the
   colony will keep working. Then deploy it —
   `nix run .#deploy-local -- tutorial-js` — spawn its first creep
   from the console tab
   (`Game.spawns['Spawn1'].spawnCreep([WORK, CARRY, MOVE], 'Harvester1')`),
   and watch until the room goes still. Compare what you saw against
   your prediction. The creep ages out at 1500 ticks and nothing in
   that script spawns another. When the creep turns around full, find
   the line that decided that.

3. Sort every statement of the tutorial JS into two columns: decision
   (role choice, thresholds, when to switch tasks) or action (Screeps
   API calls). Check the decision column against dox/creeps.dox and
   the action column against harness/main.ts — the port in this repo
   is the answer key. Where the repo has something the script lacks —
   the respawn block, the dead-memory cleanup, the role check,
   findClosestByPath in place of sources[0] — explain what each one
   is for.
4. Walk the pipeline from `dox/creeps.dox` to the server: open
   generated/index.ts (the code tab shows what's deployed; `nix run
   .#generate` writes the file into ./generated) and match each line
   back to the spec line it came from.

## Klanker Gonna Slop.

The llm will write slop. That's why we try and have some guardrails around
that. But there's no removing human judgement. Take a look at the slop in 'vm/module.nix'.

There are lines of the form
```
foo.bar = <some-value>;;
foo.baz = <some-other-value>;
```
for example, lines 12 and 13.

```
networking.hostName = "dox-populi";
networking.firewall.enable = false;
```
looks nicer this way.
```
networking = {
  hostName = "dox-populi";
  firewall.enable = false;
};
```
Fix the rest. Wax on, wax off.
