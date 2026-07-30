// FSM behavioral tests: verify transition functions produce correct states
// for critical scenarios. Run via `nix build .#checks.x86_64-linux.fsm-behavior`.
import {
  harvesterTransition,
  upgraderTransition,
  harvesterContext,
  upgraderContext,
} from "../generated/index";
import type { HarvesterState, UpgraderState, CreepEvent } from "../generated/index";

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

// ── Harvester: the spawnFull bug ────────────────────────────────────
// Scenario: harvester has a full store and the spawn is full.
// emitEvent emits "spawnFull" (compound: store full AND spawn full)
// so the FSM transitions to harvesting (idle) instead of stuck delivering.
console.log("Harvester: spawnFull while delivering");
assert(
  "delivering + spawnFull → harvesting (go back to source)",
  hTx("delivering", "spawnFull"),
  "harvesting",
);

console.log("Harvester: spawnFull while harvesting");
assert(
  "harvesting + spawnFull → harvesting (stay at source)",
  hTx("harvesting", "spawnFull"),
  "harvesting",
);

// Harvester: normal storeFull cycle (spawn NOT full, so storeFull fires).
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

// ── Upgrader: collecting + spawnFull must transition to upgrading ───
// The upgrader delivers to the controller, not the spawn. When the
// shell emits spawnFull (because spawn is full), the upgrader should
// treat it as "go upgrade with what you have" — not stay collecting.
console.log("Upgrader: spawnFull while collecting");
assert(
  "collecting + spawnFull → upgrading (upgrader doesn't deliver to spawn)",
  uTx("collecting", "spawnFull"),
  "upgrading",
);

console.log("Upgrader: spawnFull while upgrading");
assert(
  "upgrading + spawnFull → upgrading (keep upgrading)",
  uTx("upgrading", "spawnFull"),
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

// ── Multi-step scenario: full harvester cycle with spawnFull ────────
// Simulates: harvest → fill up → deliver → spawn fills → go back.
console.log("Harvester: multi-step scenario");
let hState: HarvesterState = "harvesting";
hState = hTx(hState, "tick");       // still harvesting
assert("tick while harvesting", hState, "harvesting");
hState = hTx(hState, "storeFull");  // store full, go deliver
assert("store fills up", hState, "delivering");
hState = hTx(hState, "tick");       // walking to spawn
assert("walking to spawn", hState, "delivering");
hState = hTx(hState, "spawnFull");  // arrive but spawn is full
assert("spawn is full, go back", hState, "harvesting");

// ── Summary ────────────────────────────────────────────────────────
console.log("");
if (failures > 0) {
  throw new Error(`FAILED: ${failures} assertion(s)`);
} else {
  console.log("ALL PASSED");
}
