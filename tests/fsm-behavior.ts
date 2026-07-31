// FSM behavioral tests: verify the generated transition functions AND
// the generated state behaviors against an independent restatement of
// the spec's policy tables. Run via
// `nix build .#checks.x86_64-linux.fsm-behavior`.
//
// Event vocabulary (tutorial 5): CreepEvent is a PRODUCT of three
// orthogonal facts — store level (empty|mid|full) x sink saturation
// (SinksOpen|SinksFull) x site presence (Site|NoSite) — 12 variants,
// spelled as the exact concatenation of the dimension values. TowerEvent
// is the product threat (hostile|calm) x integrity (Damage|Intact).
// One event per actor per tick, no priority, no masking: every fact
// rides every event.
//
// Test strategy, two sweeps:
//  1. Transitions: every state x every event against a policy oracle
//     restated here from the spec's documentation — proves the state
//     GRAPH routes correctly.
//  2. Behaviors: every state's {action, target} against a full restated
//     behavior table — the shell executes behaviors[state], so a
//     transition sweep alone would stay green even if codegen wired
//     e.g. supporting to 'harvest' and every "supporting" creep went
//     mining at the controller.
// The oracles are an independent second statement of the tables in
// dox/creeps.dox; if spec and oracle ever disagree, one of them is
// lying and this check fails. tsc proves the reconstructed event
// product and the oracle tables against the generated types: rename a
// spec variant and this file stops compiling.
import {
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  towerTransition,
  harvesterContext,
  upgraderContext,
  builderContext,
  towerContext,
  behaviors,
  towerBehaviors,
} from "../generated/index";
import type {
  HarvesterState,
  UpgraderState,
  BuilderState,
  TowerState,
  CreepEvent,
  TowerEvent,
  StateBehaviors,
  TowerStateBehaviors,
} from "../generated/index";

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

type Store = (typeof STORES)[number];
type Sinks = (typeof SINKS)[number];
type Sites = (typeof SITES)[number];
type Threat = (typeof THREATS)[number];
type Integrity = (typeof INTEGRITIES)[number];

const creepEvent = (st: Store, sk: Sinks, si: Sites): CreepEvent =>
  `${st}${sk}${si}`;
const towerEvent = (th: Threat, integ: Integrity): TowerEvent =>
  `${th}${integ}`;

// Helper: run a transition and return the target state.
function hTx(state: HarvesterState, event: CreepEvent): HarvesterState {
  return harvesterTransition(state, event, harvesterContext).target;
}
function uTx(state: UpgraderState, event: CreepEvent): UpgraderState {
  return upgraderTransition(state, event, upgraderContext).target;
}
function bTx(state: BuilderState, event: CreepEvent): BuilderState {
  return builderTransition(state, event, builderContext).target;
}
function tTx(state: TowerState, event: TowerEvent): TowerState {
  return towerTransition(state, event, towerContext).target;
}

// ── Policy oracles: the spec's tables, restated independently ────────

// Harvester: harvest until full, deliver until empty; nowhere to put it
// -> support the controller. empty -> harvesting; mid while harvesting
// stays (fill up first); otherwise energy on board is disposed of by
// the sink dimension: SinksOpen -> delivering, SinksFull -> supporting.
// Sites are noise to this role.
// Historical: a mid-store harvester in delivering whose sinks just
// saturated has an EMPTY transfer-target set — staying put is the same
// null-target freeze the builder once had; the *SinksFull* rows pin the
// supporting escape. Sinks reopening pulls supporting back to
// delivering because delivery powers spawning.
function harvesterOracle(
  state: HarvesterState,
  st: Store,
  sk: Sinks
): HarvesterState {
  if (st === "empty") return "harvesting";
  if (st === "mid" && state === "harvesting") return "harvesting";
  return sk === "SinksOpen" ? "delivering" : "supporting";
}

// Upgrader: collect until full, upgrade until empty; mid self-loops.
// Sinks and sites are noise to this role — the old sinksFull->upgrading
// shortcut was only ever a proxy for "store full" and dissolves here.
function upgraderOracle(state: UpgraderState, st: Store): UpgraderState {
  if (st === "full") return "upgrading";
  if (st === "empty") return "collecting";
  return state;
}

// Builder: gather until full; energy on board is spent by the site
// dimension: Site -> building, NoSite -> assisting. mid while gathering
// stays (fill up first). Sinks are noise to this role.
// Historical (both fixed by the product vocabulary, both pinned by the
// full* rows of the sweep):
//  - FROZEN builder: the old priority chain let storeFull mask the
//    residual noSites — a full builder with zero sites self-looped in
//    building (action=build, no target, no API call) until TTL death.
//    full*NoSite -> assisting is the escape, observed not deduced.
//  - BLIND builder: the compound sinksFull outranked sawSite, so a full
//    builder under sink saturation shoveled overflow at the controller
//    next to an unbuilt extension. full*Site -> building keeps sight of
//    the site regardless of the sink dimension.
function builderOracle(
  state: BuilderState,
  st: Store,
  si: Sites
): BuilderState {
  if (st === "empty") return "gathering";
  if (st === "mid" && state === "gathering") return "gathering";
  return si === "Site" ? "building" : "assisting";
}

// Tower: attack OUTRANKS repair; state-independent pure policy. The
// reference (section 5 main.js) issues repair then attack in one tick
// and lets the later intent win — engine accident as priority. The spec
// makes it explicit: hostile present -> attacking, no matter the
// integrity fact (the hostileDamage rows pin it).
function towerOracle(th: Threat, integ: Integrity): TowerState {
  if (th === "hostile") return "attacking";
  return integ === "Damage" ? "repairing" : "guarding";
}

// ── Behavior oracles: what each state DOES ───────────────────────────
// Typed as the generated StateBehaviors/TowerStateBehaviors so tsc
// enforces exhaustiveness and variant spelling; the runtime compare
// below catches wrong wiring (right shape, wrong action or target).
const creepBehaviorOracle: StateBehaviors = {
  harvesting: { action: "harvest", target: "source" },
  delivering: { action: "transfer", target: "energySink" },
  supporting: { action: "upgrade", target: "controller" },
  collecting: { action: "harvest", target: "source" },
  upgrading: { action: "upgrade", target: "controller" },
  gathering: { action: "harvest", target: "source" },
  building: { action: "build", target: "constructionSite" },
  assisting: { action: "upgrade", target: "controller" },
};

const towerBehaviorOracle: TowerStateBehaviors = {
  guarding: { action: "idle", target: "none" },
  attacking: { action: "attack", target: "hostile" },
  repairing: { action: "repair", target: "damagedStructure" },
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

console.log("Tower: exhaustive 3 states x 4 events");
for (const state of ["guarding", "attacking", "repairing"] as const) {
  for (const th of THREATS)
    for (const integ of INTEGRITIES) {
      const ev = towerEvent(th, integ);
      assert(`${state} + ${ev}`, tTx(state, ev), towerOracle(th, integ));
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

// ── Summary ────────────────────────────────────────────────────────
console.log("");
if (failures > 0) {
  throw new Error(`FAILED: ${failures} assertion(s)`);
} else {
  console.log("ALL PASSED");
}
