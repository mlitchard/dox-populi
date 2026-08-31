// dox-populi shell: the "hands". All Screeps API calls live here.
// The "brain" (types, policy, later FSMs) is generated from dox/ by Paradox.
import { harvesterBody, validCreepRole } from "../generated/index";

export const loop = (): void => {
  // Reclaim memory of dead creeps.
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
    }
  }

  const spawn = Game.spawns["Spawn1"];
  if (spawn && !spawn.spawning && Object.keys(Game.creeps).length < 1) {
    // harvesterBody: BodyPart[] from Paradox is directly assignable to
    // typed-screeps BodyPartConstant[] — no translation layer needed.
    spawn.spawnCreep(harvesterBody, `harvester-${Game.time}`, {
      memory: { role: "harvester" },
    });
  }

  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
    const role = validCreepRole(creep.memory.role);
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
  }
};
