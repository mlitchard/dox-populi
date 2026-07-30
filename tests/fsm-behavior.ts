// FSM behavioral tests: verify transition functions produce correct states
// for critical scenarios. Run via `nix build .#checks.x86_64-linux.fsm-behavior`.
//
// Event vocabulary (tutorial 3): storeEmpty, storeFull, sinksFull (creep
// full AND every energy sink — spawn + extensions — full), and the
// residual pair sawSite/noSites (construction sites exist / don't).
import {
  harvesterTransition,
  upgraderTransition,
  builderTransition,
  harvesterContext,
  upgraderContext,
  builderContext,
} from "../generated/index";
import type {
  HarvesterState,
  UpgraderState,
  BuilderState,
  CreepEvent,
} from "../generated/index";

let failures = 0;

function assert(
  label: string,
  actual: string,
  expected: string,
): void {
  if (actual === expected) {
    console.log(`  PASS: ${label}`);
  } else {
    console.log(`  FAIL: ${label} — expected "${expected}", got "${actual}"`);
    failures++;
  }
}

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

// ── Harvester: the sinksFull bug (né spawnFull) ─────────────────────
// Scenario: harvester has a full store and every energy sink is full.
// emitEvent emits "sinksFull" (compound: store full AND all sinks full)
// so the FSM transitions to harvesting (idle) instead of stuck delivering.
// Observe-first: this event fires BEFORE any doomed transfer is attempted,
// which is what makes the old ERR_FULL deadlock structurally impossible.
console.log("Harvester: sinksFull while delivering");
assert(
  "delivering + sinksFull → harvesting (go back to source)",
  hTx("delivering", "sinksFull"),
  "harvesting",
);

console.log("Harvester: sinksFull while harvesting");
assert(
  "harvesting + sinksFull → harvesting (stay at source)",
  hTx("harvesting", "sinksFull"),
  "harvesting",
);

// Harvester: normal storeFull cycle (some sink has room, storeFull fires).
console.log("Harvester: normal harvest-deliver cycle");
assert(
  "harvesting + storeFull → delivering",
  hTx("harvesting", "storeFull"),
  "delivering",
);
assert(
  "delivering + storeEmpty → harvesting",
  hTx("delivering", "storeEmpty"),
  "harvesting",
);

// Harvester: site observations are none of its business — self-loops.
console.log("Harvester: site events are self-loops");
assert(
  "harvesting + sawSite → harvesting",
  hTx("harvesting", "sawSite"),
  "harvesting",
);
assert(
  "delivering + sawSite → delivering",
  hTx("delivering", "sawSite"),
  "delivering",
);

// ── Upgrader: collecting + sinksFull must transition to upgrading ───
// The upgrader delivers to the controller, not the sinks. When the
// shell emits sinksFull, the upgrader should treat it as "go upgrade
// with what you have" — not stay collecting.
console.log("Upgrader: sinksFull while collecting");
assert(
  "collecting + sinksFull → upgrading (upgrader doesn't deliver to sinks)",
  uTx("collecting", "sinksFull"),
  "upgrading",
);

console.log("Upgrader: sinksFull while upgrading");
assert(
  "upgrading + sinksFull → upgrading (keep upgrading)",
  uTx("upgrading", "sinksFull"),
  "upgrading",
);

// Upgrader: normal collect-upgrade cycle.
console.log("Upgrader: normal collect-upgrade cycle");
assert(
  "collecting + storeFull → upgrading",
  uTx("collecting", "storeFull"),
  "upgrading",
);
assert(
  "upgrading + storeEmpty → collecting",
  uTx("upgrading", "storeEmpty"),
  "collecting",
);

// Upgrader: site observations are self-loops.
console.log("Upgrader: site events are self-loops");
assert(
  "collecting + sawSite → collecting",
  uTx("collecting", "sawSite"),
  "collecting",
);
assert(
  "upgrading + noSites → upgrading",
  uTx("upgrading", "noSites"),
  "upgrading",
);

// ── Builder: gather → build cycle ───────────────────────────────────
console.log("Builder: normal gather-build cycle");
assert(
  "gathering + storeFull → building",
  bTx("gathering", "storeFull"),
  "building",
);
assert(
  "building + storeEmpty → gathering",
  bTx("building", "storeEmpty"),
  "gathering",
);
assert(
  "building + sawSite → building (keep building)",
  bTx("building", "sawSite"),
  "building",
);

// ── Builder: the no-sites fallback policy (spec decision) ───────────
// When there is nothing to build, the builder does NOT idle — it
// assists the upgrader (action=upgrade) until a site appears.
console.log("Builder: no-sites fallback to assisting");
assert(
  "building + noSites → assisting (nothing to build, go upgrade)",
  bTx("building", "noSites"),
  "assisting",
);
assert(
  "assisting + sawSite → building (a site appeared, back to work)",
  bTx("assisting", "sawSite"),
  "building",
);
assert(
  "assisting + storeEmpty → gathering (refuel first)",
  bTx("assisting", "storeEmpty"),
  "gathering",
);
assert(
  "assisting + noSites → assisting (keep assisting)",
  bTx("assisting", "noSites"),
  "assisting",
);

// Builder: sink state is not its delivery target — sinksFull self-loops.
console.log("Builder: sinksFull is a self-loop everywhere");
assert(
  "gathering + sinksFull → gathering",
  bTx("gathering", "sinksFull"),
  "gathering",
);
assert(
  "building + sinksFull → building",
  bTx("building", "sinksFull"),
  "building",
);

// ── Multi-step scenario: builder lifecycle around a construction site ─
// Simulates: gather → fill up → build → site completes → assist →
// new site placed → build again → run dry → gather.
console.log("Builder: multi-step scenario");
let bState: BuilderState = "gathering";
bState = bTx(bState, "sawSite");     // site exists but store not full
assert("gathering while site waits", bState, "gathering");
bState = bTx(bState, "storeFull");   // full, go build
assert("store fills up", bState, "building");
bState = bTx(bState, "noSites");     // site finished under our trowel
assert("site done, fall back to assisting", bState, "assisting");
bState = bTx(bState, "sawSite");     // new site placed
assert("new site, back to building", bState, "building");
bState = bTx(bState, "storeEmpty");  // ran dry mid-build
assert("empty, back to gathering", bState, "gathering");

// ── Summary ────────────────────────────────────────────────────────
console.log("");
if (failures > 0) {
  throw new Error(`FAILED: ${failures} assertion(s)`);
} else {
  console.log("ALL PASSED");
}
