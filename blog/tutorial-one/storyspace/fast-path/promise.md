# Promise (fast path)
Each tutorial maps to the original screeps [tutorial](https://github.com/screeps/tutorial-scripts).
Along the way, you'll flex your devflow muscles by familiarizing yourself
with the process of creation, verification, and deployment.
By the end, you'll have a colony running, ready to be improved and extended.
The first tutorial will get you started with dox-populi.

We'll take a survey of the tests that nix runs.
## What you get

A Screeps colony to play with. The server runs in a VM on your
machine. The viewer runs in your browser. The program driving the
colony is two readable files, and the paradox/typscript tooling
rejects changes that fail to align with the spec.
## The shape

One VM. Inside it:

- dox/creeps.dox — the spec, written with an LLM. The Paradox checker
  verifies its named properties, and Paradox generates the decision
  logic from it.
- harness/main.ts — the TypeScript harness that makes the game calls,
  using that generated logic.
- a private game server and a browser viewer, both built by nix.

Your machine needs QEMU, tmux, curl and a browser.

## By the end

- The server and viewer are up.
- Your code is deployed; you've placed the spawn and watched the
  harvester work.
- You'll have a familiarity of how dox-populi works,
  and be ready for the next section.

## Start

- download the vm [image](https://dokyard.dev/installs/) for tutorial one.
- We'll walk through the [README](narrative.md)
- And then we'll go through the [exercises](exercises.md).
