When organizing this series, I committed to the following structure: Each tutorial must have
its own branch,
with a corresponding llm session you can read, and a vm you can run with minimal dependencies.
This post covers how I managed to
screw that up for the first post, and how I handled the error.

The problem is that the first branch meant for engagement starts with the first tutorial completed,
and works through the second one. What got lost was the initial session with claude,
which was meant to be the starting point for the series.
If I recall correctly the
initial session was me doing 'stop doing that do this instead', more or less.
This is unfortunate but not a deal-breaker. My assertion for the entire project is that in
order for the accessible on-ramp to exist, there must be someone to create the infrastructure for it.
This will be fully expressed in the final main branch, which has everything one needs
to continue an expansion of the initial tutorial with prompt engineering.
However, each branch needs to have the same workflow: git checkout, download iso, run-vm.sh.
That workflow should have existed on this branch to begin with but didn't. What this post
will cover is a reconstruction of the first javascript tutorial port,
plus the addition of the vm machinery. The session below is the repair happening.

## What you can get by engaging this branch.
How the workflow is constructed.

Getting in.
On the host: 
 (1) check out tutorial-one
 (2) put the stage ISO beside run-vm.sh, run ./run-vm.sh.
     The first run creates the disk and boots the installer once.
     It writes the prebuilt system image and powers off.
     Every run after boots the installed VM in a tmux session.
     The host needs qemu, tmux, and curl. Inside, you're auto-logged-in as dev,
     and ~/dox-populi is the mounted from the host checkout. You can edit with
     your host editor and run tools in the guest against the same files.

The environment.
nix develop in ~/dox-populi drops into the devShell, pre-baked into the VM
image so it opens without fetching anything. That shell carries all dependecies, see (link) flake.nix.

The loop.
Two files hold the program: dox/creeps.dox (the spec) and harness/main.ts
(the harness). Edit either, then nix flake check. The check rebuilds everything
from the spec each time: Paradox checks the spec and generates the decision logic
in-derivation, tsc typechecks the harness against that freshly generated logic,
esbuild assembles main.js. 
A spec edit that breaks the harness surfaces as a compile error on this run, at a line.

Delivery. nix run .#deploy rebuilds main.js from whatever the spec and harness now say,
decrypts your Screeps token (the VM points SCREEPS_IDENTITY at ~/work/identity,
the key you shared in from the host via the workdir),
and pushes to your account on screeps.com.
The server runs the new code on its next tick.
You watch the result in the room for this branch. One harvester spawning itself, harvesting, and delivering.

The shape of it: edit → check → deploy → watch, with the checks between you and the server on every pass.
The same nix flake check a reader runs being the one CI runs.(footnote: setting up a runner is beyond the scope of this tutorial)

