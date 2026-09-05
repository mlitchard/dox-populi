# Quick Start


## What you're watching in the viewer

The viewer reads your server's socket and draws its world with the
open-sourced renderer. Placing the spawn is your one manual act — the
game has always asked the player to choose that tile. Everything after
the click is the spec executing: the spawn builds a harvester, the
harvester walks to the source, fills, walks back, delivers, and starts
again. That loop on screen is this stage's deliverable — a
specification, run through the checkers, driving a live creep on a
server you host.

## Get in the Mix
[the client](mix/client.md)

## What `nix run .#server` starts

The open-source Screeps server, built from source by nix, holding a
world of its own on your machine. Once it's up, ticks pass, sources
sit ready, and the world waits for a player. State lives in
`.server-data/`

 ## Get in the Mix
 [refactoring](mix/local.md)

## What `nix run .#deploy-local` builds

The pipeline reads
`dox/creeps.dox`, Paradox verifies the spec's named properties and
generates the decision logic, tsc typechecks `harness/main.ts` against
that generated code, and the bundle lands on the server as `main.js`.
From then on the server calls that bundle every tick. Two files you
can read — the spec and the harness — are now the only player in the
world.

  ## Get in the Mix
    [breaking things](break.md)

## Next

  [exercises](exercises.md).
