## The Promise

Boot this post's VM and the room is working: one creep shuttles energy to
the spawn, another hauls it to the room controller, the structure that
levels up the room. That's the second section of the official Screeps
tutorial. Section one asked for a harvester that feeds the spawn; section
two adds an upgrader that grows the room.

This post follows the session that delivered it. Partway through, the
harvester froze at the source with a full load. The post is the story of
getting it unstuck.

What you'll learn:

1. Where the bot's decisions live: in a spec, one
   [finite-state machine](https://en.wikipedia.org/wiki/Finite-state_machine)
   per role. The harness — the code that talks to the game — reads the
   world and carries out the current state.
2. How the code-test loop turns a live bug into a failing test, and the
   failing test into a fix.
3. How to interrogate a green test.

The same job, twice. The official tutorial's harvester:

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
        else if(Game.spawns['Spawn1'].energy < Game.spawns['Spawn1'].energyCapacity) {
            if(creep.transfer(Game.spawns['Spawn1'], RESOURCE_ENERGY) == ERR_NOT_IN_RANGE) {
                creep.moveTo(Game.spawns['Spawn1']);
            }
        }
    }
};
```

The spec's harvester, the delivering state:

```
deliveringStoreEmpty: Transition HarvesterState CreepEvent CreepContext
  Transition:
    event: CreepEvent.storeEmpty
    target: HarvesterState.harvesting

deliveringStoreFull: Transition HarvesterState CreepEvent CreepContext
  Transition:
    event: CreepEvent.storeFull
    target: HarvesterState.delivering

deliveringSpawnFull: Transition HarvesterState CreepEvent CreepContext
  Transition:
    event: CreepEvent.spawnFull
    target: HarvesterState.harvesting

deliveringTick: Transition HarvesterState CreepEvent CreepContext
  Transition:
    event: CreepEvent.tick
    target: HarvesterState.delivering
```

The tutorial's harvester holds the whole job in one if/else; a full store
at a full spawn slips past both branches, and the creep stands still. The
spec writes that case down: `deliveringSpawnFull`, target `harvesting`.
Every state and event pair gets a written target, and Paradox rejects a
spec that drops one.
