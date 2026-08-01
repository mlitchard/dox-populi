// dox-populi shell: the "hands". All Screeps API calls live here.
// The "brain" (types, policy, FSMs) is generated from dox/ by Paradox.
//
// This shell is a GENERIC FSM interpreter. It knows the fixed vocabularies
// (CreepEvent, TowerEvent, Action, TargetKind) and nothing else: no role
// names, no state names, no policy constants. Roles and states flow through
// as opaque data from generated/; the only switches below are over Action
// and TargetKind.
import {
  behaviors,
  spawnQueue,
  spawnAffordBasis,
  desiredExtensions,
  extensionOffsets,
  desiredTowers,
  towerOffsets,
  towerContext,
  towerBehaviors,
  harvesterContext,
  upgraderContext,
  builderContext,
  defenderContext,
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  defenderTransition,
  towerTransition,
  validHarvesterState,
  validUpgraderState,
  validBuilderState,
  validDefenderState,
  validTowerState,
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
  DefenderState,
  TowerState,
  TowerEvent,
  ThreatLevel,
  TargetKind,
} from "../generated/index";

// ---------------------------------------------------------------------------
// Machine registry. Each generated transition function is typed over its own
// state union, and the state unions are disjoint, so the generated
// valid*State validators double as ownership guards: a machine claims a
// state by validating it, and declines (null) otherwise. step() folds over
// the registry — first machine to claim the state wins. No role dispatch
// exists anywhere else in the shell. Each machine carries its OWN event
// emitter: the worker machines observe the store/sink/site product
// (CreepEvent); the defender machine observes the room threat level — a
// defender has no carry parts, so store facts are degenerate for it (the
// contract documented in dox/creeps.dox). The tower machine is NOT in this
// registry: it runs over TowerState/TowerEvent in its own structure loop
// below, with validTowerState as the same kind of ownership guard.
// ---------------------------------------------------------------------------

interface StepResult {
  event: string;
  next: CreepState;
}

type Step = (state: CreepState, creep: Creep, obs: RoomObs) => StepResult | null;

const machines: Step[] = [
  (state, creep, obs) => {
    let s: HarvesterState;
    try {
      s = validHarvesterState(state);
    } catch {
      return null;
    }
    const event = emitEvent(creep, obs);
    return { event, next: harvesterTransition(s, event, harvesterContext).target };
  },
  (state, creep, obs) => {
    let s: UpgraderState;
    try {
      s = validUpgraderState(state);
    } catch {
      return null;
    }
    const event = emitEvent(creep, obs);
    return { event, next: upgraderTransition(s, event, upgraderContext).target };
  },
  (state, creep, obs) => {
    let s: BuilderState;
    try {
      s = validBuilderState(state);
    } catch {
      return null;
    }
    const event = emitEvent(creep, obs);
    return { event, next: builderTransition(s, event, builderContext).target };
  },
  (state, _creep, obs) => {
    let s: DefenderState;
    try {
      s = validDefenderState(state);
    } catch {
      return null;
    }
    const event = threatLevel(obs);
    return { event, next: defenderTransition(s, event, defenderContext).target };
  },
];

function step(state: CreepState, creep: Creep, obs: RoomObs): StepResult {
  for (const machine of machines) {
    const result = machine(state, creep, obs);
    if (result !== null) return result;
  }
  return { event: "unclaimed", next: state };
}

// ---------------------------------------------------------------------------
// Observation. "Energy sink" is vocabulary, not policy: a spawn, an
// extension, or a BELOW-THRESHOLD tower that can still accept delivered
// energy. The tower threshold is brain data (towerContext.energyTarget): a
// tower is a sink only while its energy is below the target. hasFreeEnergy
// is the ONE filter serving both delivery targeting (TargetKind.energySink)
// and the sinksAllFull observation — the observed fact can never contradict
// the available action. Room-level facts (sinks, sites, hostiles, damage)
// are computed once per room per tick.
// ---------------------------------------------------------------------------

type EnergySink = StructureSpawn | StructureExtension | StructureTower;

const isEnergySink = (s: AnyOwnedStructure): s is EnergySink =>
  s.structureType === STRUCTURE_SPAWN ||
  s.structureType === STRUCTURE_EXTENSION ||
  s.structureType === STRUCTURE_TOWER;

const hasFreeEnergy = (s: EnergySink): boolean =>
  s.structureType === STRUCTURE_TOWER
    ? s.store[RESOURCE_ENERGY] < towerContext.energyTarget
    : s.store.getFreeCapacity(RESOURCE_ENERGY) > 0;

const isTower = (s: AnyOwnedStructure): s is StructureTower =>
  s.structureType === STRUCTURE_TOWER;

interface RoomObs {
  sinks: EnergySink[];
  sinksAllFull: boolean;
  hasSites: boolean;
  hostiles: Creep[];
  damaged: AnyStructure[];
}

function observeRoom(room: Room, cache: Map<string, RoomObs>): RoomObs {
  const cached = cache.get(room.name);
  if (cached) return cached;
  const sinks = room.find(FIND_MY_STRUCTURES).filter(isEnergySink);
  const obs: RoomObs = {
    sinks,
    sinksAllFull: !sinks.some(hasFreeEnergy),
    hasSites: room.find(FIND_CONSTRUCTION_SITES).length > 0,
    hostiles: room.find(FIND_HOSTILE_CREEPS),
    // hits is typed number but is undefined at runtime on indestructible
    // structures (e.g. controllers); the typeof check is the mechanical
    // guard.
    damaged: room
      .find(FIND_STRUCTURES)
      .filter((s) => typeof s.hits === "number" && s.hits < s.hitsMax),
  };
  cache.set(room.name, obs);
  return obs;
}

// Exactly ONE event per creep per tick, NO priority, no masking (the
// contract documented in dox/creeps.dox): the event is the PRODUCT of three
// orthogonal facts — store level x sink saturation x site presence — and
// every fact rides every event, so masking is unrepresentable. The variant
// spelling is the literal concatenation `${store}${sinks}${sites}`; each
// part is a typed string-literal union, so tsc proves the inferred
// template-literal union is exactly the generated CreepEvent union — rename
// a spec variant and this function fails to typecheck.
function emitEvent(creep: Creep, obs: RoomObs): CreepEvent {
  const used = creep.store.getUsedCapacity(RESOURCE_ENERGY);
  const free = creep.store.getFreeCapacity(RESOURCE_ENERGY);
  const store = used === 0 ? "empty" : free === 0 ? "full" : "mid";
  const sinks = obs.sinksAllFull ? "SinksFull" : "SinksOpen";
  const sites = obs.hasSites ? "Site" : "NoSite";
  return `${store}${sinks}${sites}`;
}

// The ONE threat projection (same-filter doctrine at the type level):
// hostiles-present bit, typed as the generated ThreatLevel union. Three
// consumers share the exact value — the defender machine's event, the
// tower event's first product fact, and the DesiredCounts index in the
// spawn walk (ThreatLevel variant names ARE the DesiredCounts field
// names; tsc proves the bridge).
function threatLevel(obs: RoomObs): ThreatLevel {
  return obs.hostiles.length > 0 ? "hostile" : "calm";
}

// The tower analogue: exactly one TowerEvent per tower per tick, the
// product of the threat, integrity, and reserve facts, same
// template-literal proof. Reserve is a PER-TOWER fact (this tower's
// energy against the spec's attackReserve floor), so the event is
// emitted per tower, not per room.
function emitTowerEvent(tower: StructureTower, obs: RoomObs): TowerEvent {
  const threat = threatLevel(obs);
  const integrity = obs.damaged.length > 0 ? "Damage" : "Intact";
  const reserve =
    tower.store[RESOURCE_ENERGY] >= towerContext.attackReserve
      ? "ReserveOk"
      : "ReserveLow";
  return `${threat}${integrity}${reserve}`;
}

// ---------------------------------------------------------------------------
// Execution. A Behavior is {action, target} in the fixed vocabularies; the
// shell resolves the TargetKind from the acting object's position and
// performs the Action. The instanceof guards reconcile the action/target
// pairing the brain chose with the concrete object types the API demands.
// ---------------------------------------------------------------------------

type ActionTarget =
  | Source
  | EnergySink
  | StructureController
  | ConstructionSite
  | Creep
  | AnyStructure
  | null;

function resolveTarget(
  kind: TargetKind,
  pos: RoomPosition,
  room: Room,
  obs: RoomObs
): ActionTarget {
  switch (kind) {
    case "source":
      return pos.findClosestByPath(FIND_SOURCES);
    case "energySink":
      return pos.findClosestByPath(obs.sinks.filter(hasFreeEnergy));
    case "controller":
      return room.controller ?? null;
    case "constructionSite":
      return room.find(FIND_CONSTRUCTION_SITES)[0] ?? null;
    case "hostile":
      return pos.findClosestByRange(FIND_HOSTILE_CREEPS);
    case "damagedStructure":
      return pos.findClosestByRange(obs.damaged);
    case "none":
      return null;
  }
}

// upgradeController's return type includes ERR_ACCESS_DENIED, which
// typed-screeps keeps outside ScreepsReturnCode — hence the widened union.
type ActionResult = ScreepsReturnCode | ERR_ACCESS_DENIED | null;

function execute(behavior: Behavior, creep: Creep, obs: RoomObs): ActionResult {
  const target = resolveTarget(behavior.target, creep.pos, creep.room, obs);
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
    // attack/repair are tower verbs today, but the Action vocabulary is
    // shared and this switch stays total: for a creep they resolve
    // mechanically too — the brain simply never pairs a creep state with
    // them.
    case "attack":
      if (target instanceof Creep) result = creep.attack(target);
      break;
    case "repair":
      if (target instanceof Structure) result = creep.repair(target);
      break;
    case "idle":
      break;
  }
  if (result === ERR_NOT_IN_RANGE && target) creep.moveTo(target);
  return result;
}

// Tower execution: same fixed vocabularies, resolved from the TOWER's
// position. Towers don't move, so there is no ERR_NOT_IN_RANGE handling.
// The Action switch stays total over the shared union; verbs with no tower
// API call (harvest/transfer/upgrade/build) are mechanical no-ops the brain
// never selects for a tower state.
function executeTower(
  behavior: Behavior,
  tower: StructureTower,
  obs: RoomObs
): ActionResult {
  const target = resolveTarget(behavior.target, tower.pos, tower.room, obs);
  let result: ActionResult = null;
  switch (behavior.action) {
    case "attack":
      if (target instanceof Creep) result = tower.attack(target);
      break;
    case "repair":
      if (target instanceof Structure) result = tower.repair(target);
      break;
    case "harvest":
    case "transfer":
    case "upgrade":
    case "build":
    case "idle":
      break;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Flight recorder. A per-actor ring buffer of (tick, event, fsm, action, rc)
// in Memory.trace, appended only when the tuple CHANGES — a stuck actor
// costs one entry, not one per tick. Traces are keyed by creep NAME or
// tower ID; rc is the raw Screeps API return code (null = no call made:
// idle, or unresolvable target). Traces of dead actors are kept for
// post-mortem, pruned oldest-first past a cap. Pure observation: nothing
// reads the trace to make decisions.
// ---------------------------------------------------------------------------

const TRACE_LIMIT = 50; // max entries per actor
const TRACE_DEAD_LIMIT = 10; // max dead-actor traces kept for post-mortem

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

// A trace name counts as dead only if it is neither a live creep name nor a
// live tower id this tick — otherwise every tick's pruning would eat the
// traces of standing towers.
function pruneDeadTraces(liveTowerIds: Set<string>): void {
  if (!Memory.trace) return;
  const traces = Memory.trace;
  const lastTick = (n: string): number => {
    const log = traces[n];
    return log.length > 0 ? log[log.length - 1].t : 0;
  };
  const dead = Object.keys(traces)
    .filter((n) => !(n in Game.creeps) && !liveTowerIds.has(n))
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

// Recovery state for a tower with missing/invalid fsm memory. generate
// emits no machine-initial export for the tower (the creep analogue is
// RoleSpec.initial riding spawnQueue), so the shell derives it from spec
// data: the first field of the towerBehaviors record, which is the
// machine's initial state by spec construction, guarded by validTowerState.
// SPEC-SIDE FOLLOW-UP: export the tower machine's initial state directly so
// this derivation can be deleted.
const towerInitialState: TowerState = validTowerState(
  Object.keys(towerBehaviors)[0]
);

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

  // Live towers, observed once per tick: the same find feeds tower-memory
  // reclamation, trace pruning, placement counting, and the tower machine
  // loop below.
  const towersByRoom = new Map<string, StructureTower[]>();
  const liveTowerIds = new Set<string>();
  for (const roomName in Game.rooms) {
    const towers = Game.rooms[roomName].find(FIND_MY_STRUCTURES).filter(isTower);
    if (towers.length > 0) towersByRoom.set(roomName, towers);
    for (const t of towers) liveTowerIds.add(t.id);
  }

  // Reclaim memory of towers whose id no longer resolves — the tower
  // analogue of dead-creep reclamation.
  if (Memory.towers) {
    for (const id in Memory.towers) {
      if (!liveTowerIds.has(id)) delete Memory.towers[id];
    }
  }

  pruneDeadTraces(liveTowerIds);

  const spawn: StructureSpawn | undefined = Game.spawns["Spawn1"];
  const obsCache = new Map<string, RoomObs>();

  // Spec-driven population: walk the spawnQueue in order, spawn for the
  // first role that is under strength. Counts, tier order, and the afford
  // basis are brain data; BODYPART_COST is an engine constant, so pricing
  // a tier is observation, not policy. bodies is ordered richest-first —
  // the first affordable tier wins. If no tier is affordable this tick,
  // nobody spawns: the first under-strength role holds the spawn slot, and
  // skipping ahead to a cheaper role would be shell-invented policy.
  // desired is a DesiredCounts record indexed by the observed threat level
  // — a literal bridge, no if/else: the brain's numbers, the world's index.
  let birthsThisTick = 0;
  if (spawn && !spawn.spawning) {
    const creeps = Object.values(Game.creeps);
    const affordable = spawn.room[spawnAffordBasis];
    const threat = threatLevel(observeRoom(spawn.room, obsCache));
    const tierCost = (body: BodyPart[]): number =>
      body.reduce((sum, part) => sum + BODYPART_COST[part], 0);
    for (const spec of spawnQueue) {
      const count = creeps.filter((c) => c.memory.role === spec.role).length;
      if (count < spec.desired[threat]) {
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

  // Tower placement: the same mechanical executor, driven by desiredTowers
  // + towerOffsets. Towers unlock at RCL 3 — server legality decides, a
  // rejected offset is retried on a later tick.
  let towersBuilt = 0;
  if (spawn) {
    const room = spawn.room;
    towersBuilt = (towersByRoom.get(room.name) ?? []).length;
    const towerSites = room
      .find(FIND_MY_CONSTRUCTION_SITES)
      .filter((s) => s.structureType === STRUCTURE_TOWER);
    if (towersBuilt + towerSites.length < desiredTowers) {
      for (const o of towerOffsets) {
        const placed = room.createConstructionSite(
          spawn.pos.x + o.dx,
          spawn.pos.y + o.dy,
          STRUCTURE_TOWER
        );
        if (placed === OK) break;
      }
    }
  }

  // Generic creep loop: observe → transition (brain) → execute (hands).
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

    const { event, next } = step(state, creep, obs);
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

  // Generic tower loop: observe → transition (brain) → execute (hands).
  // Tower FSM state lives in Memory.towers[id].fsm — towers have no
  // built-in memory; validTowerState is the ownership guard, exactly like
  // the creep registry.
  const towerStats: Record<
    string,
    { event: string; fsm: string; action: string; energy: number }
  > = {};
  for (const [roomName, towers] of towersByRoom) {
    const room = Game.rooms[roomName];
    if (!room) continue;
    const obs = observeRoom(room, obsCache);
    for (const tower of towers) {
      const event = emitTowerEvent(tower, obs);
      let state: TowerState;
      try {
        state = validTowerState(Memory.towers?.[tower.id]?.fsm);
      } catch {
        state = towerInitialState;
      }
      const next = towerTransition(state, event, towerContext).target;
      (Memory.towers ??= {})[tower.id] = { fsm: next };
      const rc = executeTower(towerBehaviors[next], tower, obs);
      recordTrace(tower.id, event, next, towerBehaviors[next].action, rc);
      towerStats[tower.id] = {
        event,
        fsm: next,
        action: towerBehaviors[next].action,
        energy: tower.store[RESOURCE_ENERGY],
      };
    }
  }

  // Telemetry, observable via GET /api/user/memory?path=stats.* — the
  // contract polled by tests/integration.nix. Change them together.
  // births/deaths are cumulative: seeded from the previous tick's stats
  // (Memory persists between ticks) before this assignment replaces them.
  // spawning reads the role from Memory.creeps, which spawnCreep writes
  // synchronously — Game.creeps may not list a creep mid-spawn yet.
  // hostiles/damaged are the spawn-room observation counts (0 when no
  // spawn exists).
  const spawnObs = spawn ? observeRoom(spawn.room, obsCache) : null;

  // Combat observation: cumulative counters diffed against the previous
  // tick's snapshot, which rides stats.combat itself (Memory persists
  // between ticks — the births/deaths pattern, so no second Memory root).
  // Pure bookkeeping, no policy, nothing reads it back:
  //  - hostileMoves: observed hostile position changes (a raider that
  //    marches, latched forever);
  //  - damageTaken: summed observed hit-point drops on own creeps and
  //    own-room structures (a raider that lands blows, latched);
  //  - hostilesDowned: hostiles that vanished from the spawn room — NPC
  //    creeps never cross room edges, so gone means dead.
  // Snapshot rebuild is from live objects only; dead entries fall out
  // naturally. A structure first seen damaged counts its drop from
  // hitsMax (structures enter observation at full health).
  const prevCombat = Memory.stats?.combat;
  const hostileSnap: Record<string, { x: number; y: number; hits: number }> =
    {};
  const hitsSnap: Record<string, number> = {};
  let hostileMoves = prevCombat?.hostileMoves ?? 0;
  let damageTaken = prevCombat?.damageTaken ?? 0;
  let hostilesDowned = prevCombat?.hostilesDowned ?? 0;
  if (spawnObs) {
    for (const h of spawnObs.hostiles) {
      hostileSnap[h.id] = { x: h.pos.x, y: h.pos.y, hits: h.hits };
      const p = prevCombat?.hostiles[h.id];
      if (p && (p.x !== h.pos.x || p.y !== h.pos.y)) hostileMoves += 1;
    }
    for (const id in prevCombat?.hostiles ?? {}) {
      if (!(id in hostileSnap)) hostilesDowned += 1;
    }
    for (const name in Game.creeps) {
      const c = Game.creeps[name];
      hitsSnap[name] = c.hits;
      const before = prevCombat?.hits[name] ?? c.hitsMax;
      if (c.hits < before) damageTaken += before - c.hits;
    }
    for (const s of spawnObs.damaged) {
      hitsSnap[s.id] = s.hits;
      const before = prevCombat?.hits[s.id] ?? s.hitsMax;
      if (s.hits < before) damageTaken += before - s.hits;
    }
  }

  Memory.stats = {
    spawnEnergy: spawn ? spawn.store[RESOURCE_ENERGY] : 0,
    controllerProgress: spawn?.room.controller?.progress ?? 0,
    controllerLevel: spawn?.room.controller?.level ?? 0,
    extensionsBuilt,
    extensionProgress,
    towersBuilt,
    spawning: spawn?.spawning
      ? Memory.creeps[spawn.spawning.name]?.role ?? null
      : null,
    roleCounts,
    births: (Memory.stats?.births ?? 0) + birthsThisTick,
    deaths: (Memory.stats?.deaths ?? 0) + deathsThisTick,
    creeps: creepStats,
    towers: towerStats,
    hostiles: spawnObs ? spawnObs.hostiles.length : 0,
    damaged: spawnObs ? spawnObs.damaged.length : 0,
    combat: {
      hostileMoves,
      damageTaken,
      hostilesDowned,
      hostiles: hostileSnap,
      hits: hitsSnap,
    },
  };
};
