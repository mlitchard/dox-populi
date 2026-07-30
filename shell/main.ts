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

// A creep with missing/invalid fsm memory gets the initial state of the
// spec whose role matches its own — pure data comparison against spawnQueue,
// not a role literal.
function initialStateFor(creep: Creep): CreepState | null {
  const spec = spawnQueue.find((s) => s.role === creep.memory.role);
  return spec ? spec.initial : null;
}

export const loop = (): void => {
  // Reclaim memory of dead creeps.
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
    }
  }

  const spawn: StructureSpawn | undefined = Game.spawns["Spawn1"];

  // Spec-driven population: walk the spawnQueue in order, spawn for the
  // first role that is under strength. Counts and bodies are brain data.
  if (spawn && !spawn.spawning) {
    const creeps = Object.values(Game.creeps);
    for (const spec of spawnQueue) {
      const count = creeps.filter((c) => c.memory.role === spec.role).length;
      if (count < spec.desired) {
        spawn.spawnCreep(spec.body, `${spec.role}-${Game.time}`, {
          memory: { role: spec.role, fsm: spec.initial },
        });
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
    { role: string; event: string; fsm: string; action: string }
  > = {};

  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
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
    execute(behaviors[next], creep, obs);

    creepStats[name] = {
      role: creep.memory.role,
      event,
      fsm: next,
      action: behaviors[next].action,
    };
  }

  // Telemetry, observable via GET /api/user/memory?path=stats.* — the
  // contract polled by tests/integration.nix. Change them together.
  Memory.stats = {
    spawnEnergy: spawn ? spawn.store[RESOURCE_ENERGY] : 0,
    controllerProgress: spawn?.room.controller?.progress ?? 0,
    controllerLevel: spawn?.room.controller?.level ?? 0,
    extensionsBuilt,
    extensionProgress,
    creeps: creepStats,
  };
};
