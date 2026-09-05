// Colony bundle entry point: built by flake.nix (esbuild -> main.js)
// and deployed as the player's code. Each tick it runs every creep and
// tower through the generated FSMs (dox/creeps.dox -> generated/index.ts),
// executes the spec's spawn queue and construction plans, and publishes
// Memory.stats telemetry.
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

// The worker machines emit CreepEvent; the defender emits ThreatLevel.
interface StepResult {
  event: string;
  next: CreepState;
}

// One machine's try at a creep tick; null means the state is outside
// this machine's union.
type Step = (state: CreepState, creep: Creep, obs: RoomObs) => StepResult | null;

// One entry per role machine. A machine claims a creep by validating
// its FSM state: the validator throws on states outside its union, so
// the creep passes to the next machine. This works because no state
// name appears in two machines' unions; the spec keeps them disjoint.
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

// Runs one creep tick through whichever machine owns its state.
// CreepState covers exactly the four machines' states, so "unclaimed"
// can only appear when a spec machine is missing from this registry.
function step(state: CreepState, creep: Creep, obs: RoomObs): StepResult {
  for (const machine of machines) {
    const result = machine(state, creep, obs);
    if (result !== null) return result;
  }
  return { event: "unclaimed", next: state };
}

// The structures that receive creep energy deliveries. This set gives
// the spec's SinksOpen/SinksFull facts and energySink target their
// meaning.
type EnergySink = StructureSpawn | StructureExtension | StructureTower;

const isEnergySink = (s: AnyOwnedStructure): s is EnergySink =>
  s.structureType === STRUCTURE_SPAWN ||
  s.structureType === STRUCTURE_EXTENSION ||
  s.structureType === STRUCTURE_TOWER;

// A tower asks for energy only after dropping below energyTarget, and
// then keeps asking until it is filled back up to refillTarget. This
// stops creeps from making a delivery trip after every small spend.
const towerRefillLatch = (t: StructureTower): boolean => {
  const latches = (Memory.towerRefill ??= {});
  const energy = t.store[RESOURCE_ENERGY];
  const open = latches[t.id]
    ? energy < towerContext.refillTarget
    : energy < towerContext.energyTarget;
  latches[t.id] = open;
  return open;
};

// A spawn or extension can take energy while it has free capacity. A
// tower can take energy while its store is below refillTarget, which
// is the level where refills stop.
const hasFreeEnergy = (s: EnergySink): boolean =>
  s.structureType === STRUCTURE_TOWER
    ? s.store[RESOURCE_ENERGY] < towerContext.refillTarget
    : s.store.getFreeCapacity(RESOURCE_ENERGY) > 0;

const isTower = (s: AnyOwnedStructure): s is StructureTower =>
  s.structureType === STRUCTURE_TOWER;

// What the shell observed in a room this tick. Every creep and tower
// in the room reads the same snapshot for events and targeting.
interface RoomObs {
  sinks: EnergySink[];
  sinksAllFull: boolean;
  hasSites: boolean;
  hostiles: Creep[];
  damaged: AnyStructure[];
}

// The cache is created each tick in loop, so a room is scanned once
// per tick and every consumer sees the same snapshot.
function observeRoom(room: Room, cache: Map<string, RoomObs>): RoomObs {
  const cached = cache.get(room.name);
  if (cached) return cached;
  const sinks = room.find(FIND_MY_STRUCTURES).filter(isEnergySink);
  const obs: RoomObs = {
    sinks,
    sinksAllFull: !sinks.some(hasFreeEnergy),
    hasSites: room.find(FIND_CONSTRUCTION_SITES).length > 0,
    hostiles: room.find(FIND_HOSTILE_CREEPS),
    // hits is undefined at runtime on indestructible structures despite the type declaration.
    damaged: room
      .find(FIND_STRUCTURES)
      .filter((s) => typeof s.hits === "number" && s.hits < s.hitsMax),
  };
  cache.set(room.name, obs);
  return obs;
}

// Builds the event name from three answers: the creep's store level
// (empty, mid, full), whether every sink is full, and whether any
// construction site exists. The return type makes any name outside
// the generated CreepEvent union a compile error.
function emitEvent(creep: Creep, obs: RoomObs): CreepEvent {
  const used = creep.store.getUsedCapacity(RESOURCE_ENERGY);
  const free = creep.store.getFreeCapacity(RESOURCE_ENERGY);
  const store = used === 0 ? "empty" : free === 0 ? "full" : "mid";
  const sinks = obs.sinksAllFull ? "SinksFull" : "SinksOpen";
  const sites = obs.hasSites ? "Site" : "NoSite";
  return `${store}${sinks}${sites}`;
}

// The single threat reading. Three consumers: the defender's event,
// the first fact of the tower event, and the spawn policy's
// desired-count key.
function threatLevel(obs: RoomObs): ThreatLevel {
  return obs.hostiles.length > 0 ? "hostile" : "calm";
}

// Builds the event name from three answers: the threat level, whether
// any structure is damaged, and whether this tower's own energy meets
// attackReserve. The return type makes any name outside the generated
// TowerEvent union a compile error.
function emitTowerEvent(tower: StructureTower, obs: RoomObs): TowerEvent {
  const threat = threatLevel(obs);
  const integrity = obs.damaged.length > 0 ? "Damage" : "Intact";
  const reserve =
    tower.store[RESOURCE_ENERGY] >= towerContext.attackReserve
      ? "ReserveOk"
      : "ReserveLow";
  return `${threat}${integrity}${reserve}`;
}

// Everything a spec target kind can resolve to; null when resolution
// found nothing.
type ActionTarget =
  | Source
  | EnergySink
  | StructureController
  | ConstructionSite
  | Creep
  | AnyStructure
  | null;

// Picks the actual game object for the brain's target kind from this
// tick's observation; null when nothing qualifies. A tower mid-refill
// takes priority over every other open sink.
function resolveTarget(
  kind: TargetKind,
  pos: RoomPosition,
  room: Room,
  obs: RoomObs
): ActionTarget {
  switch (kind) {
    case "source":
      return pos.findClosestByPath(FIND_SOURCES);
    case "energySink": {
      const open = obs.sinks.filter(hasFreeEnergy);
      const latchedTowers = open.filter(
        (s): s is StructureTower => isTower(s) && towerRefillLatch(s)
      );
      return pos.findClosestByPath(latchedTowers.length > 0 ? latchedTowers : open);
    }
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

// Everything executing an action can yield; null when no API call was
// made.
type ActionResult = ScreepsReturnCode | ERR_ACCESS_DENIED | null;

// Makes the Screeps API call for the behavior's action on its resolved
// target; null means no call was made (idle, or no valid target). When
// the action is out of range the creep moves toward the target, and
// the returned ERR_NOT_IN_RANGE means it is on its way.
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

// The action vocabulary is shared with creeps, so the switch covers
// all of it; a tower implements attack and repair only.
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

const TRACE_LIMIT = 50;
const TRACE_DEAD_LIMIT = 10;

// Appends to an actor's Memory.trace log only when the
// event/fsm/action/rc tuple changed since the last entry, so a
// one-tick blip stays visible until TRACE_LIMIT later changes evict
// it. The itest probes in tests/integration.nix poll these traces.
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

// Caps dead actors' traces at TRACE_DEAD_LIMIT, evicting the stalest
// first, so recent post-mortems stay available without Memory growing
// with every death.
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

// Recovery for a creep whose fsm memory failed validation: the spec's
// spawnQueue supplies its role's initial state, or null for a role
// the spec does not know.
function initialStateFor(creep: Creep): CreepState | null {
  const spec = spawnQueue.find((s) => s.role === creep.memory.role);
  return spec ? spec.initial : null;
}

// The generated towerBehaviors object lists states in spec order, so
// its first key is the tower machine's starting state.
const towerInitialState: TowerState = validTowerState(
  Object.keys(towerBehaviors)[0]
);

// Ties the pipeline together each tick, in order: dead-actor memory
// reclamation, spawning, construction placement, the creep and tower
// FSM cycles, then telemetry. creep.memory.fsm and Memory.towers carry
// the FSM states across ticks.
export const loop = (): void => {
  let deathsThisTick = 0;
  for (const name in Memory.creeps) {
    if (!(name in Game.creeps)) {
      delete Memory.creeps[name];
      deathsThisTick += 1;
    }
  }

  const towersByRoom = new Map<string, StructureTower[]>();
  const liveTowerIds = new Set<string>();
  for (const roomName in Game.rooms) {
    const towers = Game.rooms[roomName].find(FIND_MY_STRUCTURES).filter(isTower);
    if (towers.length > 0) towersByRoom.set(roomName, towers);
    for (const t of towers) liveTowerIds.add(t.id);
  }

  if (Memory.towers) {
    for (const id in Memory.towers) {
      if (!liveTowerIds.has(id)) delete Memory.towers[id];
    }
  }
  if (Memory.towerRefill) {
    for (const id in Memory.towerRefill) {
      if (!liveTowerIds.has(id)) delete Memory.towerRefill[id];
    }
  }

  pruneDeadTraces(liveTowerIds);

  const spawn: StructureSpawn | undefined = Game.spawns["Spawn1"];
  const obsCache = new Map<string, RoomObs>();

  let birthsThisTick = 0;
  // spawnQueue order is priority: the first role below its desired count
  // gets the attempt, and when no body tier is affordable the spawn
  // waits there. The spec lists body tiers richest-first, so find picks
  // the best affordable one.
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

  const creepStats: Record<
    string,
    { role: string; event: string; fsm: string; action: string; parts: number }
  > = {};
  const roleCounts: Record<string, number> = {};

  for (const name in Game.creeps) {
    const creep = Game.creeps[name];
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

  // One record per tower this tick, filled during the tower cycle and
  // published as Memory.stats.towers.
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

  const spawnObs = spawn ? observeRoom(spawn.room, obsCache) : null;

  // This tick's hostile positions and hit points are compared with the
  // snapshot saved in Memory.stats.combat last tick; movement, damage,
  // and kills found in the comparison are added to running totals, and
  // this tick's snapshot is saved for the next comparison.
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

  // The colony's telemetry, published each tick for readers outside the
  // game loop.
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
