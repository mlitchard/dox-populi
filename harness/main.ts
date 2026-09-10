// dox-populi harness: all Screeps API calls live here.
// The decision logic is generated from the spec (dox/) by Paradox.
import { harvesterBody, validCreepRole } from "../generated/index";

const TRACE_LIMIT = 50;
const TRACE_DEAD_LIMIT = 10;

// Appends to a creep's Memory.trace log only when the action/rc pair
// changed since the last entry, so a one-tick blip stays visible until
// TRACE_LIMIT later changes evict it.
function recordTrace(name: string, action: string, rc: number | null): void {
  const traces = (Memory.trace ??= {});
  const log = (traces[name] ??= []);
  const last = log[log.length - 1];
  if (last && last.action === action && last.rc === rc) return;
  log.push({ t: Game.time, action, rc });
  if (log.length > TRACE_LIMIT) log.shift();
}

// Caps dead creeps' traces at TRACE_DEAD_LIMIT, evicting the stalest
// first, so recent post-mortems stay available without Memory growing
// with every death.
function pruneDeadTraces(): void {
  if (!Memory.trace) return;
  const traces = Memory.trace;
  const lastTick = (n: string): number => {
    const log = traces[n];
    return log.length > 0 ? log[log.length - 1].t : 0;
  };
  const dead = Object.keys(traces)
    .filter((n) => !(n in Game.creeps))
    .sort((a, b) => lastTick(a) - lastTick(b));
  while (dead.length > TRACE_DEAD_LIMIT) delete traces[dead.shift()!];
}

export const loop = (): void => {
  // Reclaim memory of dead creeps.
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
    }
  }
  pruneDeadTraces();

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
        if (source) {
          const rc = creep.harvest(source);
          if (rc === ERR_NOT_IN_RANGE) {
            recordTrace(name, "moveTo", creep.moveTo(source));
          } else {
            recordTrace(name, "harvest", rc);
          }
        }
      } else if (spawn) {
        const rc = creep.transfer(spawn, RESOURCE_ENERGY);
        if (rc === ERR_NOT_IN_RANGE) {
          recordTrace(name, "moveTo", creep.moveTo(spawn));
        } else {
          recordTrace(name, "transfer", rc);
        }
      }
    }
  }
};
