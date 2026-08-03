// dox-populi invader shell: the ENEMY's "hands". This bundle runs as the
// seeded "raiders" NPC user's users.code on the private server — the
// flake's seed step injects both the user and the code, so the raider is
// world content. (NOT uid 2: the engine special-cases the stock Invader
// user's creeps and bars it from the runner roster.) Same church, second
// congregation: ALL raider decision logic lives in dox/invader/
// invader.dox; this file only observes, transitions, and executes. The
// only switches below are over InvaderAction and InvaderTargetKind.
//
// The creeps this brain drives are provisioned externally (the itest's
// surgeryInsertInvader; natural NPC events) — this user has no spawn and
// spawns nothing.
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

// ---------------------------------------------------------------------------
// Observation. attackRange is the ONE range constant serving both reach
// facts and the attack action (same-filter doctrine, brain data). Lowest-id
// sort is a mechanical tie-break, not policy: reproducible aggression is
// this brain's contract.
// ---------------------------------------------------------------------------

const byId = <T extends { id: string }>(a: T, b: T): number =>
  a.id < b.id ? -1 : a.id > b.id ? 1 : 0;

interface RaiderObs {
  foes: Creep[];
  structs: AnyOwnedStructure[];
  spawn: StructureSpawn | null;
}

function observe(creep: Creep): RaiderObs {
  return {
    foes: creep.pos
      .findInRange(FIND_HOSTILE_CREEPS, invaderContext.attackRange)
      .sort(byId),
    // The controller is excluded as unattackable — mirrored in the spec's
    // struct-reach fact so the observation never promises an impossible
    // action.
    structs: creep.pos
      .findInRange(FIND_HOSTILE_STRUCTURES, invaderContext.attackRange)
      .filter((s) => s.structureType !== STRUCTURE_CONTROLLER)
      .sort(byId),
    spawn: creep.pos.findClosestByRange(FIND_HOSTILE_SPAWNS),
  };
}

// Exactly ONE event per raider per tick, the product of three orthogonal
// facts — foe reach x struct reach x spawn sight — spelled as the template
// literal `${foe}${struct}${spawn}`; tsc proves the inferred union is
// exactly the generated InvaderEvent union (the contract documented in
// dox/invader/invader.dox).
function emitInvaderEvent(obs: RaiderObs): InvaderEvent {
  const foe = obs.foes.length > 0 ? "foe" : "noFoe";
  const struct = obs.structs.length > 0 ? "Struct" : "NoStruct";
  const spawn = obs.spawn ? "Spawn" : "NoSpawn";
  return `${foe}${struct}${spawn}`;
}

// ---------------------------------------------------------------------------
// Execution over the fixed vocabularies.
// ---------------------------------------------------------------------------

type RaiderTarget = Creep | AnyOwnedStructure | StructureSpawn | null;

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
      // repathTicks is brain data: 0 recomputes the path every tick.
      if (target)
        result = creep.moveTo(target, { reusePath: invaderContext.repathTicks });
      break;
    case "idle":
      break;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Flight recorder — the colony shell's Memory.trace discipline exactly
// (shell/main.ts recordTrace): per-raider entries {t, event, fsm, action,
// rc}, appended ONLY when the tuple changes — a steady state is one line,
// not one per tick. rc is the raw Screeps API return code captured AFTER
// execute (null = no call made: idle, or unresolvable target). ONE
// deliberate difference from the colony: NO dead-trace pruning. A dead
// raider's fsm memory is reclaimed, but its trace LATCHES forever — the
// fight resolves in ticks and the corpses clear; the trace is the
// tombstone that talks. Pure telemetry: nothing reads it to decide.
// ---------------------------------------------------------------------------

const TRACE_LIMIT = 50; // max entries per raider

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

// Recovery state for a raider with missing/invalid fsm memory: the first
// field of the invaderBehaviors record, which is the machine's initial
// state by spec construction (the field-order contract documented in
// dox/invader/invader.dox — tower precedent).
const invaderInitialState: InvaderState = validInvaderState(
  Object.keys(invaderBehaviors)[0]
);

export const loop = (): void => {
  // Reclaim memory of dead raiders — but NOT their traces (see above).
  const raiders = (Memory.raiders ??= {});
  for (const name in raiders) {
    if (!(name in Game.creeps)) delete raiders[name];
  }

  // Generic raider loop: observe → transition (brain) → execute (hands).
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
