// Enemy bundle entry point: built standalone by flake.nix (invaderMain)
// and seeded on the private server as the "raiders" NPC user's code.
// Each tick it runs every raider through the generated invader FSM
// (dox/invader/ -> generated/invader.ts).
// FIND_HOSTILE_* is relative to the caller.
import {
  invaderBehaviors,
  invaderContext,
  invaderTransition,
  validInvaderState,
} from "../generated/invader";
import type {
  InvaderBehavior,
  InvaderEvent,
  InvaderState,
  InvaderTargetKind,
} from "../generated/invader";

// Sort comparator: orders by id so find results are deterministic
// and target selection (foes[0], structs[0]) is stable across ticks.
const byId = <T extends { id: string }>(a: T, b: T): number =>
  a.id < b.id ? -1 : a.id > b.id ? 1 : 0;

// One raider's view of the world this tick: attackables within
// attackRange (foes, structs) and the closest enemy spawn in the room.
// Feeds both event emission and target resolution.
interface RaiderObs {
  foes: Creep[];
  structs: AnyOwnedStructure[];
  spawn: StructureSpawn | null;
}

// Samples the world around one raider. foes/structs are scoped by the
// spec's attackRange, which defines the FSM's foe/Struct reach facts.
function observe(creep: Creep): RaiderObs {
  return {
    foes: creep.pos
      .findInRange(FIND_HOSTILE_CREEPS, invaderContext.attackRange)
      .sort(byId),
    // Controller is unattackable; filter mirrors the spec's struct-reach fact.
    structs: creep.pos
      .findInRange(FIND_HOSTILE_STRUCTURES, invaderContext.attackRange)
      .filter((s) => s.structureType !== STRUCTURE_CONTROLLER)
      .sort(byId),
    spawn: creep.pos.findClosestByRange(FIND_HOSTILE_SPAWNS),
  };
}

// Builds the event name from three yes/no answers: foe in reach,
// structure in reach, spawn in the room. tsc checks the result
// against the generated InvaderEvent union.
function emitInvaderEvent(obs: RaiderObs): InvaderEvent {
  const foe = obs.foes.length > 0 ? "foe" : "noFoe";
  const struct = obs.structs.length > 0 ? "Struct" : "NoStruct";
  const spawn = obs.spawn ? "Spawn" : "NoSpawn";
  return `${foe}${struct}${spawn}`;
}

type RaiderTarget = Creep | AnyOwnedStructure | StructureSpawn | null;

// Picks the actual game object for the brain's target kind from this
// tick's observation; null when nothing qualifies.
function resolveTarget(kind: InvaderTargetKind, obs: RaiderObs): RaiderTarget {
  switch (kind) {
    case "foeInReach":
      return obs.foes[0] ?? null;
    case "structInReach":
      return obs.structs[0] ?? null;
    case "hostileSpawn":
      return obs.spawn;
    case "none":
      return null;
  }
}

// Makes the Screeps API call for the behavior's action on its resolved
// target. Returns the call's return code; null means no call was made
// this tick (idle, or no valid target).
function execute(
  behavior: InvaderBehavior,
  creep: Creep,
  obs: RaiderObs
): ScreepsReturnCode | null {
  const target = resolveTarget(behavior.target, obs);
  let result: ScreepsReturnCode | null = null;
  switch (behavior.action) {
    case "attack":
      if (target instanceof Creep || target instanceof Structure)
        result = creep.attack(target);
      break;
    case "march":
      if (target)
        result = creep.moveTo(target, { reusePath: invaderContext.repathTicks });
      break;
    case "idle":
      break;
  }
  return result;
}

// No dead-trace pruning: raider traces latch permanently.
const TRACE_LIMIT = 50;

// Appends to this raider's Memory.trace log only when the
// event/fsm/action/rc tuple changed since the last entry, so a
// one-tick blip stays visible until TRACE_LIMIT later changes evict it.
function recordTrace(
  name: string,
  event: string,
  fsm: string,
  action: string,
  rc: number | null
): void {
  const traces = (Memory.trace ??= {});
  const log = (traces[name] ??= []);
  const last = log[log.length - 1];
  if (
    last &&
    last.event === event &&
    last.fsm === fsm &&
    last.action === action &&
    last.rc === rc
  )
    return;
  log.push({ t: Game.time, event, fsm, action, rc });
  if (log.length > TRACE_LIMIT) log.shift();
}

// First field of invaderBehaviors = initial state by spec field-order contract.
const invaderInitialState: InvaderState = validInvaderState(
  Object.keys(invaderBehaviors)[0]
);

// Ties the pipeline together per raider: observation becomes an event,
// the event drives the transition, the new state's behavior is executed
// and traced. Memory.raiders carries each FSM state across ticks.
export const loop = (): void => {
  const raiders = (Memory.raiders ??= {});
  for (const name in raiders) {
    if (!(name in Game.creeps)) delete raiders[name];
  }

  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
    if (creep.spawning) continue;
    const obs = observe(creep);
    let state: InvaderState;
    try {
      state = validInvaderState(raiders[name]?.fsm);
    } catch {
      state = invaderInitialState;
    }
    const event = emitInvaderEvent(obs);
    const next = invaderTransition(state, event, invaderContext).target;
    raiders[name] = { fsm: next };
    const behavior = invaderBehaviors[next];
    const rc = execute(behavior, creep, obs);
    recordTrace(name, event, next, behavior.action, rc);
  }
};
