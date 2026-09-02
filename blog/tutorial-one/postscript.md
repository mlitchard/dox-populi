# Postscript

Exercises, grouped by the objective each one serves. All of them run
on the `tutorial-one` branch.

## Objective 1 — read the smallest state

- Read `dox/creeps.dox` and `harness/main.ts`. Mark every Screeps API
  call; all of them sit in the harness. Find where the creep's body
  comes from; it comes from the spec.

## Objective 2 — what each check rejects

- Remove `work` from the `BodyPart` union while `harvesterBody` still
  references `BodyPart.work`, then run `paradox check`. Read the
  rejection: "Field not found", pointing at the exact line of the
  dangling reference.
- Restore the spec. Change the harness's role branch to compare
  against a role the union does not declare, then run
  `nix flake check`. Read the compile error: `tsc` reports the
  comparison has no overlap, naming both sides and the line.

## Objective 3 — deliver and watch

- Start the private server (`nix run .#server`), push your code
  (`nix run .#deploy-local`), and open the viewer (`nix run .#client`)
  in your browser. Place your spawn, then watch the harvester spawn,
  harvest, and deliver.

## Assignment

<!-- TODO: the session prompt that starts the harvester/upgrader
stage — the ground of post one (1-tutorial-one). Exact prompt artifact
chosen at draft time. -->
