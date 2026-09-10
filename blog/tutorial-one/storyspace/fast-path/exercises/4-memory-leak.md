# Memory Leak Autopsy

The server keeps a JSON object called `Memory` for your code between
ticks. The section-1 JS never touches it. The port does: every
harvester is spawned with `{ role: "harvester" }` in its memory, and
`validCreepRole` reads it back each tick. Creep memory outlives the
creep — when a creep dies, its entry in `Memory.creeps` stays until
something deletes it.

The port's harness opens with the cleanup:

```ts
for (const name in Memory.creeps) {
  if (!(name in Game.creeps)) {
    delete Memory.creeps[name];
  }
}
```

This challenge removes that hygiene and watches what grows.

1. With the port deployed, print the ledger from the console tab:

   ```js
   JSON.stringify(Object.keys(Memory.creeps))
   ```

   Note what it holds, and note the `memory` byte count in the
   panel's account header.
2. Comment out the cleanup loop in `harness/main.ts` and run
   `nix run .#deploy-local`. Both gates pass.
3. Each replacement creep gets a fresh name — `harvester-<tick>`.
   Write down what the ledger and the byte count will do as creeps
   die and are replaced.
4. Retire the harvester a few times from the console:

   ```js
   Object.values(Game.creeps)[0].suicide()
   ```

   Print the ledger, read the byte count, and hold both against what
   you wrote.
5. Write down what happens to the ledger when the cleanup returns.
   Restore the loop, deploy, print once more, and compare.

## Questions worth a minute

- What would a checker have had to name to catch this before it
  shipped?
- The account header's byte count moved. What writes that number,
  and what did it witness?
- `Memory.trace` also keeps records of the dead. Find the lines in
  `harness/main.ts` that bound them — what would the byte count do
  without those lines?
