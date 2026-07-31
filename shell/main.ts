// dox-populi shell: the "hands". All Screeps API calls live here.
// The "brain" (types, policy, FSMs) is generated from dox/ by Paradox.
//
// This shell is a GENERIC FSM interpreter. It knows the fixed vocabularies
// (CreepEvent, Action, TargetKind) and nothing else: no role names, no
// state names, no policy constants. Roles and states flow through as opaque
// data from generated/; the only switches below are over Action and
// TargetKind.
import {
  behaviors,
  spawnQueue,
  spawnAffordBasis,
  desiredExtensions,
  extensionOffsets,
  harvesterContext,
  upgraderContext,
  builderContext,
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  validHarvesterState,
  validUpgraderState,
  validBuilderState,
  validCreepState,
} from "../generated/index";
import type {
  Behavior,
  BodyPart,
  CreepEvent,
  CreepState,
  HarvesterState,
  UpgraderState,
  BuilderState,
  TargetKind,
} from "../generated/index";

// ---------------------------------------------------------------------------
// Machine registry. Each generated transition function is typed over its own
// state union, and the state unions are disjoint, so the generated
// valid*State validators double as ownership guards: a machine claims a
// state by validating it, and declines (null) otherwise. step() folds over
// the registry — first machine to claim the state wins. No role dispatch
// exists anywhere else in the shell.
// ---------------------------------------------------------------------------

type Step = (state: CreepState, event: CreepEvent) => CreepState | null;

const machines: Step[] = [
  (state, event) => {
    let s: HarvesterState;
    try {
      s = validHarvesterState(state);
    } catch {
      return null;
    }
    return harvesterTransition(s, event, harvesterContext).target;
  },
  (state, event) => {
    let s: UpgraderState;
    try {
      s = validUpgraderState(state);
    } catch {
      return null;
    }
    return upgraderTransition(s, event, upgraderContext).target;
  },
  (state, event) => {
    let s: BuilderState;
    try {
      s = validBuilderState(state);
    } catch {
      return null;
    }
    return builderTransition(s, event, builderContext).target;
  },
];

function step(state: CreepState, event: CreepEvent): CreepState {
  for (const machine of machines) {
    const next = machine(state, event);
    if (next !== null) return next;
  }
  return state;
}

// ---------------------------------------------------------------------------
// Observation. "Energy sink" is vocabulary, not policy: a spawn or extension
// whose energy store can still accept energy. Room-level facts (sinks,
// construction sites) are computed once per room per tick.
// ---------------------------------------------------------------------------

type EnergySink = StructureSpawn | StructureExtension;

const isEnergySink = (s: AnyOwnedStructure): s is EnergySink =>
  s.structureType === STRUCTURE_SPAWN || s.structureType === STRUCTURE_EXTENSION;

const hasFreeEnergy = (s: EnergySink): boolean =>
  s.store.getFreeCapacity(RESOURCE_ENERGY) > 0;

interface RoomObs {
  sinks: EnergySink[];
  sinksAllFull: boolean;
  hasSites: boolean;
}

function observeRoom(room: Room, cache: Map<string, RoomObs>): RoomObs {
  const cached = cache.get(room.name);
  if (cached) return cached;
  const sinks = room.find(FIND_MY_STRUCTURES).filter(isEnergySink);
  const obs: RoomObs = {
    sinks,
    sinksAllFull: !sinks.some(hasFreeEnergy),
    hasSites: room.find(FIND_CONSTRUCTION_SITES).length > 0,
  };
  cache.set(room.name, obs);
  return obs;
}

// Exactly one event per creep per tick, fixed priority (the contract
// documented in dox/creeps.dox):
//   storeEmpty > sinksFull > storeFull > sawSite/noSites.
// sinksFull requires the creep to be full AND every sink in the room full;
// sawSite/noSites is the residual observation about construction sites.
function emitEvent(creep: Creep, obs: RoomObs): CreepEvent {
  if (creep.store.getUsedCapacity(RESOURCE_ENERGY) === 0) return "storeEmpty";
  const storeFull = creep.store.getFreeCapacity(RESOURCE_ENERGY) === 0;
  if (storeFull && obs.sinksAllFull) return "sinksFull";
  if (storeFull) return "storeFull";
  return obs.hasSites ? "sawSite" : "noSites";
}

// ---------------------------------------------------------------------------
// Execution. A Behavior is {action, target} in the fixed vocabularies; the
// shell resolves the TargetKind to a world object and performs the Action.
// The instanceof guards reconcile the action/target pairing the brain chose
// with the concrete object types the API demands.
// ---------------------------------------------------------------------------

type ActionTarget =
  | Source
  | EnergySink
  | StructureController
  | ConstructionSite
  | null;

function resolveTarget(kind: TargetKind, creep: Creep, obs: RoomObs): ActionTarget {
  switch (kind) {
    case "source":
      return creep.pos.findClosestByPath(FIND_SOURCES);
    case "energySink":
      return creep.pos.findClosestByPath(obs.sinks.filter(hasFreeEnergy));
    case "controller":
      return creep.room.controller ?? null;
    case "constructionSite":
      return creep.room.find(FIND_CONSTRUCTION_SITES)[0] ?? null;
    case "none":
      return null;
  }
}

// upgradeController's return type includes ERR_ACCESS_DENIED, which
// typed-screeps keeps outside ScreepsReturnCode — hence the widened union.
type ActionResult = ScreepsReturnCode | ERR_ACCESS_DENIED | null;

function execute(behavior: Behavior, creep: Creep, obs: RoomObs): ActionResult {
  const target = resolveTarget(behavior.target, creep, obs);
  let result: ActionResult = null;
  switch (behavior.action) {
    case "harvest":
      if (target instanceof Source) result = creep.harvest(target);
      break;
    case "transfer":
      if (target instanceof Structure) result = creep.transfer(target, RESOURCE_ENERGY);
      break;
    case "upgrade":
      if (target instanceof StructureController) result = creep.upgradeController(target);
      break;
    case "build":
      if (target instanceof ConstructionSite) result = creep.build(target);
      break;
    case "idle":
      break;
  }
  if (result === ERR_NOT_IN_RANGE && target) creep.moveTo(target);
  return result;
}

// ---------------------------------------------------------------------------
// Flight recorder. A per-creep ring buffer of (tick, event, fsm, action, rc)
// in Memory.trace, appended only when the tuple CHANGES — a stuck creep costs
// one entry, not one per tick. rc is the raw Screeps API return code from
// execute() (null = no call made: idle, or unresolvable target). Traces of
// dead creeps are kept for post-mortem, pruned oldest-first past a cap.
// Pure observation: nothing reads the trace to make decisions.
// ---------------------------------------------------------------------------

const TRACE_LIMIT = 50; // max entries per creep
const TRACE_DEAD_LIMIT = 10; // max dead-creep traces kept for post-mortem

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

// A creep with missing/invalid fsm memory gets the initial state of the
// spec whose role matches its own — pure data comparison against spawnQueue,
// not a role literal.
function initialStateFor(creep: Creep): CreepState | null {
  const spec = spawnQueue.find((s) => s.role === creep.memory.role);
  return spec ? spec.initial : null;
}

export const loop = (): void => {
  // Reclaim memory of dead creeps. Each reclaimed name is one observed
  // death; the cumulative counter is settled in the stats block below.
  let deathsThisTick = 0;
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
      deathsThisTick += 1;
    }
  }
  pruneDeadTraces();

  const spawn: StructureSpawn | undefined = Game.spawns["Spawn1"];

  // Spec-driven population: walk the spawnQueue in order, spawn for the
  // first role that is under strength. Counts, tier order, and the afford
  // basis are brain data; BODYPART_COST is an engine constant, so pricing
  // a tier is observation, not policy. bodies is ordered richest-first —
  // the first affordable tier wins. If no tier is affordable this tick,
  // nobody spawns: the first under-strength role holds the spawn slot, and
  // skipping ahead to a cheaper role would be shell-invented policy.
  let birthsThisTick = 0;
  if (spawn && !spawn.spawning) {
    const creeps = Object.values(Game.creeps);
    const affordable = spawn.room[spawnAffordBasis];
    const tierCost = (body: BodyPart[]): number =>
      body.reduce((sum, part) => sum + BODYPART_COST[part], 0);
    for (const spec of spawnQueue) {
      const count = creeps.filter((c) => c.memory.role === spec.role).length;
      if (count < spec.desired) {
        const body = spec.bodies.find((b) => tierCost(b) <= affordable);
        if (body) {
          const result = spawn.spawnCreep(body, `${spec.role}-${Game.time}`, {
            memory: { role: spec.role, fsm: spec.initial },
          });
          if (result === OK) birthsThisTick += 1;
        }
        break;
      }
    }
  }

  // Extension placement: mechanical executor of the spec's site plan. The
  // brain says how many extensions and which offsets; the server decides
  // what's legal (RCL, terrain) — a rejected offset just gets retried on a
  // later tick.
  let extensionsBuilt = 0;
  let extensionProgress = 0;
  if (spawn) {
    const room = spawn.room;
    extensionsBuilt = room
      .find(FIND_MY_STRUCTURES)
      .filter((s) => s.structureType === STRUCTURE_EXTENSION).length;
    const extensionSites = room
      .find(FIND_MY_CONSTRUCTION_SITES)
      .filter((s) => s.structureType === STRUCTURE_EXTENSION);
    extensionProgress = extensionSites.reduce((sum, s) => sum + s.progress, 0);
    if (extensionsBuilt + extensionSites.length < desiredExtensions) {
      for (const o of extensionOffsets) {
        const placed = room.createConstructionSite(
          spawn.pos.x + o.dx,
          spawn.pos.y + o.dy,
          STRUCTURE_EXTENSION
        );
        if (placed === OK) break;
      }
    }
  }

  // Generic creep loop: observe → transition (brain) → execute (hands).
  const obsCache = new Map<string, RoomObs>();
  const creepStats: Record<
    string,
    { role: string; event: string; fsm: string; action: string; parts: number }
  > = {};
  const roleCounts: Record<string, number> = {};

  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
    // Mechanical tally of live creeps per role — includes creeps whose fsm
    // memory is invalid, since they are alive regardless.
    roleCounts[creep.memory.role] = (roleCounts[creep.memory.role] ?? 0) + 1;
    const obs = observeRoom(creep.room, obsCache);

    let state: CreepState;
    try {
      state = validCreepState(creep.memory.fsm);
    } catch {
      const init = initialStateFor(creep);
      if (init === null) continue; // unknown role: nothing to interpret
      state = init;
    }

    const event = emitEvent(creep, obs);
    const next = step(state, event);
    creep.memory.fsm = next;
    const rc = execute(behaviors[next], creep, obs);
    recordTrace(name, event, next, behaviors[next].action, rc);

    creepStats[name] = {
      role: creep.memory.role,
      event,
      fsm: next,
      action: behaviors[next].action,
      parts: creep.body.length,
    };
  }

  // Telemetry, observable via GET /api/user/memory?path=stats.* — the
  // contract polled by tests/integration.nix. Change them together.
  // births/deaths are cumulative: seeded from the previous tick's stats
  // (Memory persists between ticks) before this assignment replaces them.
  // spawning reads the role from Memory.creeps, which spawnCreep writes
  // synchronously — Game.creeps may not list a creep mid-spawn yet.
  Memory.stats = {
    spawnEnergy: spawn ? spawn.store[RESOURCE_ENERGY] : 0,
    controllerProgress: spawn?.room.controller?.progress ?? 0,
    controllerLevel: spawn?.room.controller?.level ?? 0,
    extensionsBuilt,
    extensionProgress,
    spawning: spawn?.spawning
      ? Memory.creeps[spawn.spawning.name]?.role ?? null
      : null,
    roleCounts,
    births: (Memory.stats?.births ?? 0) + birthsThisTick,
    deaths: (Memory.stats?.deaths ?? 0) + deathsThisTick,
    creeps: creepStats,
  };
};
