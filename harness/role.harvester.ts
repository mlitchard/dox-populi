// Mirrors tutorial-js/section1/role.harvester.js: one creep's harvest
// round trip between the room's source and Spawn1.

const TRACE_LIMIT = 50;

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

export function run(creep: Creep): void {
  if (creep.store.getFreeCapacity() > 0) {
    const source = creep.pos.findClosestByPath(FIND_SOURCES);
    if (source) {
      const rc = creep.harvest(source);
      if (rc === ERR_NOT_IN_RANGE) {
        recordTrace(creep.name, "moveTo", creep.moveTo(source));
      } else {
        recordTrace(creep.name, "harvest", rc);
      }
    }
  } else {
    const spawn = Game.spawns["Spawn1"];
    if (spawn) {
      const rc = creep.transfer(spawn, RESOURCE_ENERGY);
      if (rc === ERR_NOT_IN_RANGE) {
        recordTrace(creep.name, "moveTo", creep.moveTo(spawn));
      } else {
        recordTrace(creep.name, "transfer", rc);
      }
    }
  }
}
