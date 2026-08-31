# Promise

<!-- Title: unruled. Off-series, unnumbered; linked between post zero
and post one. -->

Every numbered post in this series stands on two artifacts: a branch
you can check out and a session transcript you can read. The branch
holds the code at that stage; the transcript records the work that
produced it, as it happened. This page covers the step that has
neither: the section 1 work predates the repo's history, so there is
no branch holding its code and no transcript recording its sessions.

The project's transcripts begin at Screeps tutorial section 2. The
section 1 work — the first spec, the first harness, the first green
checks — happened before capture began. I looked for a session to
publish and confirmed the hole: the earliest transcript on file treats
the section 1 code as a finished artifact already being deployed.

The temptation was to stage one. Sit down with the agent, pretend
section 1 was being built for the first time, publish the result as the
record. That idea died in the session you're about to read, for the
reason this series exists: the record is evidence, and one fake entry
poisons all of it.

What you get instead is a repair, made in the open. The repo's earliest
commit is a period artifact — the state the recorded history actually
stood on. The section 1 baseline on the `tutorial-one` branch is that
commit with two lines removed: the `upgrader` and `builder` roles,
declared in the spec ahead of the section 2 work and given behavior
nowhere. That is the whole derivation claim, and the last exercise on
this page is you checking it with one `git diff`.

## What you'll learn

1. How to read the smallest complete state of the apparatus: a spec
   with one union and one constant, a harness with one loop, a flake
   with three checks.
2. How to read what each check rejects: `paradox check` verifies the
   spec's named properties; `tsc` makes a mismatch between the harness
   and the generated decision logic a compile error; the build
   assembles the bundle the server runs.
3. How to deliver code to the Screeps server and watch it run.
4. How to audit a project record: determine what it witnesses, find
   its holes, and check a derived claim against the commits.

## Side by side: the harvester

The official tutorial's section 1 harvester:

```js
var roleHarvester = {

    /** @param {Creep} creep **/
    run: function(creep) {
        if(creep.store.getFreeCapacity() > 0) {
            var sources = creep.room.find(FIND_SOURCES);
            if(creep.harvest(sources[0]) == ERR_NOT_IN_RANGE) {
                creep.moveTo(sources[0]);
            }
        }
        else {
            if(creep.transfer(Game.spawns['Spawn1'], RESOURCE_ENERGY) == ERR_NOT_IN_RANGE) {
                creep.moveTo(Game.spawns['Spawn1']);
            }
        }
    }
};
```

The role branch of the loop in `harness/main.ts` on `tutorial-one`:

```ts
if (role === "harvester") {
  if (creep.store.getFreeCapacity() > 0) {
    const source = creep.pos.findClosestByPath(FIND_SOURCES);
    if (source && creep.harvest(source) === ERR_NOT_IN_RANGE) {
      creep.moveTo(source);
    }
  } else {
    if (
      spawn &&
      creep.transfer(spawn, RESOURCE_ENERGY) === ERR_NOT_IN_RANGE
    ) {
      creep.moveTo(spawn);
    }
  }
}
```

That snippet is a slice. The full harness loop carries two more blocks,
and the reason is worth stating plainly. In the official tutorial, you
spawn the creep yourself by typing a command into the game console.
This project's colony runs unattended, so the harness does that job in
code: an auto-spawn block builds one harvester whenever the spawn is
free and the colony has none, and a reclaim block deletes the memory of
dead creeps so the respawn cycle stays clean. Read `harness/main.ts`
top to bottom — it is one short file — and you'll see the whole
division of labor: reclaim, spawn, then the role branch above.

The role and the creep's body come from the spec:

```
union CreepRole
  harvester

union BodyPart
  work
  carry
  move

harvesterBody: [BodyPart]
  [BodyPart.work, BodyPart.carry, BodyPart.move]
```

Paradox checks that spec and generates the decision logic the harness
imports. At this stage the split looks like ceremony — one role, one
body, a harness that still makes every choice. The posts that follow
are the split earning its keep.

## Equipment

- A machine with QEMU. Everything else comes on the ISO.
- The stage ISO: <!-- TODO: Hetzner link --> Boot it in QEMU and the
  development environment is already inside — Determinate Nix, the
  devShell, the checkers. The session you're about to read ran on a
  host with nix installed; the installer that removes that requirement
  was built later in the series, and this ISO is that fix applied
  backward to this stage.
- The `tutorial-one` branch, checked out inside the VM.
