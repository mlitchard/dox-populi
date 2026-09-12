// dox-populi harness: all Screeps API calls live here.
// The decision logic is generated from the spec (dox/) by Paradox.
import { harvesterBody, validCreepRole } from "../generated/index";
// The payload carries role.harvester as its own module, matching the
// tutorial layout; esbuild leaves this require for the server to resolve.
import * as roleHarvester from "role.harvester";

const TRACE_DEAD_LIMIT = 10;

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
      roleHarvester.run(creep);
    }
  }
};
