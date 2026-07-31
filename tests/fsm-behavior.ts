// FSM behavioral tests: verify the generated transition functions against
// an independent restatement of the spec's policy tables. Run via
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
// Test strategy: the dimension arrays below reconstruct the full event
// product (tsc proves the template-literal union matches the generated
// union — same contract the shell's emitEvent relies on), and each
// machine is checked EXHAUSTIVELY: every state x every event against a
// policy oracle restated here from the spec's documentation. The oracle
// is an independent second statement of the tables in dox/creeps.dox;
// if spec and oracle ever disagree, one of them is lying and this check
// fails. Named regression sections then pin the two historical
// priority-chain bugs to specific pairs.
import {
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  towerTransition,
  harvesterContext,
  upgraderContext,
  builderContext,
  towerContext,
} from "../generated/index";
import type {
  HarvesterState,
  UpgraderState,
  BuilderState,
  TowerState,
  CreepEvent,
  TowerEvent,
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
// tsc verifies each `${store}${sinks}${sites}` template below is
// assignable to CreepEvent (and `${threat}${integrity}` to TowerEvent):
// rename a spec variant and this file stops compiling.

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
// the sink dimension: SinksOpen -> delivering, SinksFull -> supporting
// (the null-target-stall escape). Sites are noise to this role.
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
function builderOracle(
  state: BuilderState,
  st: Store,
  si: Sites
): BuilderState {
  if (st === "empty") return "gathering";
  if (st === "mid" && state === "gathering") return "gathering";
  return si === "Site" ? "building" : "assisting";
}

// Tower: attack OUTRANKS repair; state-independent pure policy.
function towerOracle(th: Threat, integ: Integrity): TowerState {
  if (th === "hostile") return "attacking";
  return integ === "Damage" ? "repairing" : "guarding";
}

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

// ── Regression: the FROZEN builder (historical, fixed on this branch) ─
// Under the old priority chain, storeFull outranked the residual
// noSites, so a full builder in building with zero sites kept receiving
// storeFull and self-looped: action=build, no target, no API call, idle
// until TTL death (births 105 / deaths 100 on the live server). The
// product makes the corner directly observable: full*NoSite routes to
// assisting — observed, not deduced from a timing argument.
console.log("Regression: frozen builder (full + NoSite is observed, not masked)");
assert(
  "building + fullSinksOpenNoSite → assisting",
  bTx("building", "fullSinksOpenNoSite"),
  "assisting"
);
assert(
  "building + fullSinksFullNoSite → assisting",
  bTx("building", "fullSinksFullNoSite"),
  "assisting"
);

// ── Regression: the BLIND builder (historical, fixed on this branch) ──
// Under the old chain, the compound sinksFull outranked sawSite, so a
// full builder under sink saturation could never see a site and
// shoveled overflow at the controller next to an unbuilt extension.
// Now the site fact rides the event regardless of the sink dimension.
console.log("Regression: blind builder (site visible under saturation)");
assert(
  "building + fullSinksFullSite → building (kept sight of the site)",
  bTx("building", "fullSinksFullSite"),
  "building"
);
assert(
  "assisting + fullSinksFullSite → building (pulled back to work)",
  bTx("assisting", "fullSinksFullSite"),
  "building"
);

// ── Regression: harvester null-target-stall escapes ──────────────────
// A mid-store harvester in delivering whose sinks just saturated has an
// EMPTY transfer-target set — staying put is the same freeze signature
// the builder had. The spec routes it to supporting (spend the
// remainder on the controller); when the sinks reopen, delivery
// outranks controller-feeding because it powers spawning.
console.log("Regression: harvester never stalls on a saturated sink set");
assert(
  "delivering + midSinksFullNoSite → supporting (no transfer target)",
  hTx("delivering", "midSinksFullNoSite"),
  "supporting"
);
assert(
  "supporting + midSinksOpenNoSite → delivering (sinks reopened)",
  hTx("supporting", "midSinksOpenNoSite"),
  "delivering"
);
assert(
  "delivering + fullSinksFullNoSite → supporting (full and saturated)",
  hTx("delivering", "fullSinksFullNoSite"),
  "supporting"
);

// ── Tower priority: attack outranks repair ───────────────────────────
// The reference (section 5 main.js) issues repair then attack in one
// tick and lets the later intent win — engine accident as priority.
// The spec makes it explicit: hostile present -> attacking, no matter
// the integrity fact.
console.log("Tower: attack outranks repair");
assert(
  "repairing + hostileDamage → attacking (drop the wrench, draw the gun)",
  tTx("repairing", "hostileDamage"),
  "attacking"
);

// ── Multi-step scenario: builder lifecycle around a construction site ─
// gather → fill up → build → site completes mid-drain → assist →
// new site placed → back to building → run dry → gather.
console.log("Builder: multi-step scenario");
let bState: BuilderState = "gathering";
bState = bTx(bState, "midSinksOpenSite"); // site exists, store not full
assert("gathering while site waits", bState, "gathering");
bState = bTx(bState, "fullSinksOpenSite"); // full, go build
assert("store fills up", bState, "building");
bState = bTx(bState, "midSinksOpenNoSite"); // site finished under our trowel
assert("site done, fall back to assisting", bState, "assisting");
bState = bTx(bState, "midSinksOpenSite"); // new site placed
assert("new site, back to building", bState, "building");
bState = bTx(bState, "emptySinksOpenSite"); // ran dry mid-build
assert("empty, back to gathering", bState, "gathering");

// ── Summary ────────────────────────────────────────────────────────
console.log("");
if (failures > 0) {
  throw new Error(`FAILED: ${failures} assertion(s)`);
} else {
  console.log("ALL PASSED");
}
