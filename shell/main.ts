// dox-populi shell: the "hands". All Screeps API calls live here.
// The "brain" (types, policy, FSMs) is generated from dox/ by Paradox.
import {
  harvesterBody,
  upgraderBody,
  desiredHarvesters,
  desiredUpgraders,
  harvesterInitialState,
  upgraderInitialState,
  harvesterTransition,
  upgraderTransition,
  harvesterContext,
  upgraderContext,
  validCreepRole,
  validHarvesterState,
  validUpgraderState,
} from "../generated/index";
import type { CreepEvent } from "../generated/index";

function emitEvent(creep: Creep, spawn: StructureSpawn | undefined): CreepEvent {
  if (creep.store.getUsedCapacity(RESOURCE_ENERGY) === 0) return "storeEmpty";
  const storeFull = creep.store.getFreeCapacity(RESOURCE_ENERGY) === 0;
  const spawnFull = spawn ? spawn.store.getFreeCapacity(RESOURCE_ENERGY) === 0 : false;
  if (storeFull && spawnFull) return "spawnFull";
  if (storeFull) return "storeFull";
  return "tick";
}

export const loop = (): void => {
  // Reclaim memory of dead creeps.
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
    }
  }

  const spawn = Game.spawns["Spawn1"];

  // Spec-driven population management: harvesters first, then upgraders.
  if (spawn && !spawn.spawning) {
    const creeps = Object.values(Game.creeps);
    const harvesterCount = creeps.filter(c => c.memory.role === "harvester").length;
    const upgraderCount = creeps.filter(c => c.memory.role === "upgrader").length;

    if (harvesterCount < desiredHarvesters) {
      spawn.spawnCreep(harvesterBody, `harvester-${Game.time}`, {
        memory: { role: "harvester", fsm: harvesterInitialState },
      });
    } else if (upgraderCount < desiredUpgraders) {
      spawn.spawnCreep(upgraderBody, `upgrader-${Game.time}`, {
        memory: { role: "upgrader", fsm: upgraderInitialState },
      });
    }
  }

  // FSM-driven creep loop: observe → transition (brain) → execute (hands).
  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
    const role = validCreepRole(creep.memory.role);
    const event = emitEvent(creep, spawn);

    if (role === "harvester") {
      const currentState = validHarvesterState(creep.memory.fsm ?? harvesterInitialState);
      const { target } = harvesterTransition(currentState, event, harvesterContext);
      creep.memory.fsm = target;

      switch (target) {
        case "harvesting": {
          const source = creep.pos.findClosestByPath(FIND_SOURCES);
          if (source && creep.harvest(source) === ERR_NOT_IN_RANGE) {
            creep.moveTo(source);
          }
          break;
        }
        case "delivering": {
          if (spawn && creep.transfer(spawn, RESOURCE_ENERGY) === ERR_NOT_IN_RANGE) {
            creep.moveTo(spawn);
          }
          break;
        }
      }
    } else if (role === "upgrader") {
      const currentState = validUpgraderState(creep.memory.fsm ?? upgraderInitialState);
      const { target } = upgraderTransition(currentState, event, upgraderContext);
      creep.memory.fsm = target;

      switch (target) {
        case "collecting": {
          const source = creep.pos.findClosestByPath(FIND_SOURCES);
          if (source && creep.harvest(source) === ERR_NOT_IN_RANGE) {
            creep.moveTo(source);
          }
          break;
        }
        case "upgrading": {
          const controller = creep.room.controller;
          if (controller && creep.upgradeController(controller) === ERR_NOT_IN_RANGE) {
            creep.moveTo(controller);
          }
          break;
        }
      }
    }
  }

  // Telemetry, observable via GET /api/user/memory?path=stats.*
  // The integration test polls spawnEnergy, controllerProgress, and
  // per-creep event/state for verifying emitEvent in the game runtime.
  const creepStats: Record<string, { role: string; event: string; fsm: string }> = {};
  for (const name in Game.creeps) {
    const c = Game.creeps[name];
    creepStats[name] = {
      role: c.memory.role,
      event: emitEvent(c, spawn),
      fsm: String(c.memory.fsm),
    };
  }
  Memory.stats = {
    spawnEnergy: spawn ? spawn.store[RESOURCE_ENERGY] : 0,
    controllerProgress: spawn?.room?.controller?.progress ?? 0,
    creeps: creepStats,
  };
};
