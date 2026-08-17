// FSM behavioral tests: generated transition functions and state
// behaviors vs an independent restatement of the spec's policy tables.
// Run via `nix build .#checks.x86_64-linux.fsm-behavior`.
//
// Two sweeps — transitions (every state x every event) and behaviors
// (every state's {action, target}); a transition sweep alone stays
// green under miswired behaviors. tsc proves the oracles against the
// generated types, so a spec vocabulary change fails compile here.
import {
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  defenderTransition,
  towerTransition,
  harvesterContext,
  upgraderContext,
  builderContext,
  defenderContext,
  towerContext,
  behaviors,
  towerBehaviors,
} from "../generated/index";
import type {
  HarvesterState,
  UpgraderState,
  BuilderState,
  DefenderState,
  TowerState,
  CreepEvent,
  TowerEvent,
  ThreatLevel,
  StateBehaviors,
  TowerStateBehaviors,
} from "../generated/index";
import { invaderTransition, invaderContext, invaderBehaviors } from "../generated/invader";
import type {
  InvaderState,
  InvaderEvent,
  InvaderStateBehaviors,
} from "../generated/invader";

let failures = 0;

function assert(label: string, actual: string, expected: string): void {
  if (actual === expected) {
    console.log(`  PASS: ${label}`);
  } else {
    console.log(`  FAIL: ${label} — expected "${expected}", got "${actual}"`);
    failures++;
  }
}

// ── The event product, reconstructed ─────────────────────────────────

const STORES = ["empty", "mid", "full"] as const;
const SINKS = ["SinksOpen", "SinksFull"] as const;
const SITES = ["Site", "NoSite"] as const;
const THREATS = ["hostile", "calm"] as const;
const INTEGRITIES = ["Damage", "Intact"] as const;
const RESERVES = ["ReserveOk", "ReserveLow"] as const;
const FOES = ["foe", "noFoe"] as const;
const STRUCTS = ["Struct", "NoStruct"] as const;
const SPAWNSIGHTS = ["Spawn", "NoSpawn"] as const;

type Store = (typeof STORES)[number];
type Sinks = (typeof SINKS)[number];
type Sites = (typeof SITES)[number];
type Threat = (typeof THREATS)[number];
type Integrity = (typeof INTEGRITIES)[number];
type Reserve = (typeof RESERVES)[number];
type Foe = (typeof FOES)[number];
type Struct = (typeof STRUCTS)[number];
type SpawnSight = (typeof SPAWNSIGHTS)[number];

const threatEvent = (th: Threat): ThreatLevel => th;

const creepEvent = (st: Store, sk: Sinks, si: Sites): CreepEvent =>
  `${st}${sk}${si}`;
const towerEvent = (th: Threat, integ: Integrity, rs: Reserve): TowerEvent =>
  `${th}${integ}${rs}`;
const invaderEvent = (f: Foe, s: Struct, sp: SpawnSight): InvaderEvent =>
  `${f}${s}${sp}`;

function hTx(state: HarvesterState, event: CreepEvent): HarvesterState {
  return harvesterTransition(state, event, harvesterContext).target;
}
function uTx(state: UpgraderState, event: CreepEvent): UpgraderState {
  return upgraderTransition(state, event, upgraderContext).target;
}
function bTx(state: BuilderState, event: CreepEvent): BuilderState {
  return builderTransition(state, event, builderContext).target;
}
function dTx(state: DefenderState, event: ThreatLevel): DefenderState {
  return defenderTransition(state, event, defenderContext).target;
}
function tTx(state: TowerState, event: TowerEvent): TowerState {
  return towerTransition(state, event, towerContext).target;
}
function iTx(state: InvaderState, event: InvaderEvent): InvaderState {
  return invaderTransition(state, event, invaderContext).target;
}

// ── Policy oracles: the spec's tables, restated independently ────────

function harvesterOracle(
  state: HarvesterState,
  st: Store,
  sk: Sinks
): HarvesterState {
  if (st === "empty") return "harvesting";
  if (st === "mid" && state === "harvesting") return "harvesting";
  return sk === "SinksOpen" ? "delivering" : "supporting";
}

function upgraderOracle(state: UpgraderState, st: Store): UpgraderState {
  if (st === "full") return "upgrading";
  if (st === "empty") return "collecting";
  return state;
}

function builderOracle(
  state: BuilderState,
  st: Store,
  si: Sites
): BuilderState {
  if (st === "empty") return "gathering";
  if (st === "mid" && state === "gathering") return "gathering";
  return si === "Site" ? "building" : "assisting";
}

function defenderOracle(th: Threat): DefenderState {
  return th === "hostile" ? "engaging" : "patrolling";
}

function towerOracle(th: Threat, integ: Integrity, rs: Reserve): TowerState {
  if (th === "hostile") return "attacking";
  if (integ === "Damage" && rs === "ReserveOk") return "repairing";
  return "guarding";
}

function invaderOracle(f: Foe, s: Struct, sp: SpawnSight): InvaderState {
  if (f === "foe") return "slaughtering";
  if (s === "Struct") return "razing";
  if (sp === "Spawn") return "marching";
  return "loitering";
}

// ── Behavior oracles: what each state DOES ───────────────────────────
// Typed as the generated records so tsc enforces exhaustiveness and
// spelling; the runtime compare catches wrong wiring.
const creepBehaviorOracle: StateBehaviors = {
  harvesting: { action: "harvest", target: "source" },
  delivering: { action: "transfer", target: "energySink" },
  supporting: { action: "upgrade", target: "controller" },
  collecting: { action: "harvest", target: "source" },
  upgrading: { action: "upgrade", target: "controller" },
  gathering: { action: "harvest", target: "source" },
  building: { action: "build", target: "constructionSite" },
  assisting: { action: "upgrade", target: "controller" },
  patrolling: { action: "idle", target: "none" },
  engaging: { action: "attack", target: "hostile" },
};

const towerBehaviorOracle: TowerStateBehaviors = {
  guarding: { action: "idle", target: "none" },
  attacking: { action: "attack", target: "hostile" },
  repairing: { action: "repair", target: "damagedStructure" },
};

const invaderBehaviorOracle: InvaderStateBehaviors = {
  marching: { action: "march", target: "hostileSpawn" },
  slaughtering: { action: "attack", target: "foeInReach" },
  razing: { action: "attack", target: "structInReach" },
  loitering: { action: "idle", target: "none" },
};

// ── Exhaustive sweeps: every state x every event, oracle vs generated ─

console.log("Harvester: exhaustive 3 states x 12 events");
for (const state of ["harvesting", "delivering", "supporting"] as const) {
  for (const st of STORES)
    for (const sk of SINKS)
      for (const si of SITES) {
        const ev = creepEvent(st, sk, si);
        assert(`${state} + ${ev}`, hTx(state, ev), harvesterOracle(state, st, sk));
      }
}

console.log("Upgrader: exhaustive 2 states x 12 events");
for (const state of ["collecting", "upgrading"] as const) {
  for (const st of STORES)
    for (const sk of SINKS)
      for (const si of SITES) {
        const ev = creepEvent(st, sk, si);
        assert(`${state} + ${ev}`, uTx(state, ev), upgraderOracle(state, st));
      }
}

console.log("Builder: exhaustive 3 states x 12 events");
for (const state of ["gathering", "building", "assisting"] as const) {
  for (const st of STORES)
    for (const sk of SINKS)
      for (const si of SITES) {
        const ev = creepEvent(st, sk, si);
        assert(`${state} + ${ev}`, bTx(state, ev), builderOracle(state, st, si));
      }
}

console.log("Defender: exhaustive 2 states x 2 events");
for (const state of ["patrolling", "engaging"] as const) {
  for (const th of THREATS) {
    const ev = threatEvent(th);
    assert(`${state} + ${ev}`, dTx(state, ev), defenderOracle(th));
  }
}

console.log("Tower: exhaustive 3 states x 8 events");
for (const state of ["guarding", "attacking", "repairing"] as const) {
  for (const th of THREATS)
    for (const integ of INTEGRITIES)
      for (const rs of RESERVES) {
        const ev = towerEvent(th, integ, rs);
        assert(`${state} + ${ev}`, tTx(state, ev), towerOracle(th, integ, rs));
      }
}

console.log("Invader: exhaustive 4 states x 8 events");
for (const state of [
  "marching",
  "slaughtering",
  "razing",
  "loitering",
] as const) {
  for (const f of FOES)
    for (const s of STRUCTS)
      for (const sp of SPAWNSIGHTS) {
        const ev = invaderEvent(f, s, sp);
        assert(`invader ${state} + ${ev}`, iTx(state, ev), invaderOracle(f, s, sp));
      }
}

// ── Exhaustive behavior sweep: every state's action+target vs oracle ─

console.log("Behaviors: every creep state's action + target");
for (const state of Object.keys(creepBehaviorOracle) as (keyof StateBehaviors)[]) {
  assert(
    `${state}.action`,
    behaviors[state].action,
    creepBehaviorOracle[state].action
  );
  assert(
    `${state}.target`,
    behaviors[state].target,
    creepBehaviorOracle[state].target
  );
}

console.log("Behaviors: every tower state's action + target");
for (const state of Object.keys(towerBehaviorOracle) as (keyof TowerStateBehaviors)[]) {
  assert(
    `tower ${state}.action`,
    towerBehaviors[state].action,
    towerBehaviorOracle[state].action
  );
  assert(
    `tower ${state}.target`,
    towerBehaviors[state].target,
    towerBehaviorOracle[state].target
  );
}

console.log("Behaviors: every invader state's action + target");
for (const state of Object.keys(invaderBehaviorOracle) as (keyof InvaderStateBehaviors)[]) {
  assert(
    `invader ${state}.action`,
    invaderBehaviors[state].action,
    invaderBehaviorOracle[state].action
  );
  assert(
    `invader ${state}.target`,
    invaderBehaviors[state].target,
    invaderBehaviorOracle[state].target
  );
}

// ── Summary ────────────────────────────────────────────────────────
console.log("");
if (failures > 0) {
  throw new Error(`FAILED: ${failures} assertion(s)`);
} else {
  console.log("ALL PASSED");
}
