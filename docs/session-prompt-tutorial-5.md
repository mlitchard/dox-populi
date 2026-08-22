# Session prompt: tutorial 5 — event vocabulary reform + tower

## Problem

Two problems, one branch, deliberately coupled:

1. **The event contract is structurally flawed.** One event per tick,
   priority `storeEmpty > sinksFull > storeFull > sawSite|noSites`,
   where `sinksFull` is compound (store × sinks) and site observations
   are residual. Priority masking has now caused two live bugs:
   - Frozen builder (FIXED): full builder + 0 sites could never observe
     `noSites`; froze in `building` until TTL death. Patched with the
     `buildingStoreFull → assisting` escape (dox/creeps.dox ~502-512 has
     the reachability argument).
   - Blind builder (OPEN, bounded): full builder in a saturated economy
     (`sinksFull`) cannot observe `sawSite`; shovels overflow next to an
     unbuilt site for up to a spawn cycle. Diagnosis in session
     transcript; the agreed policy answer: full + saturated → build if
     a site exists, else assist.
   Masking bugs will keep coming from this shape. The vocabulary must
   be reformed BEFORE new observations pile on.

2. **Tutorial 5 (Defend Your Room)** — the final section. Reference:
   `~/github/tutorial-scripts/section5/`. Tower repairs damaged
   structures and attacks hostiles (main.js); harvester adds
   `STRUCTURE_TOWER` to its delivery sinks (role.harvester.js). The
   tower is the FIRST NON-CREEP MACHINE — it needs RCL 3, energy
   deliveries, and its own FSM. Expected end state: RCL 3 room, tower
   built and fed, invader shot dead, damaged structures repaired,
   sections 1–4 economy unharmed throughout.

These are one job: the tower forces new observations (hostile present,
structures damaged, tower-as-sink), which is exactly why the vocabulary
reform happens first, once, with the full observation set in view.

## Plan

### Act 1 — observation vocabulary reform (spec + shell emitEvent)

Redesign creep observations as ORTHOGONAL facts instead of a masked
priority chain: store level (empty/partial/full) × sink saturation ×
site presence — extended with what the tower port needs. Encoding is an
in-session design decision (enriched event union vs. product/record
observation fed to guarded transitions — whatever Paradox's Machine
verification handles cleanly; mind the check/generate asymmetry,
docs/paradox-check-generate-asymmetry.md). Requirements:

- Machines stay total over the new observation type (generate enforces).
- Carry forward the SEMANTIC decisions already won (they are the spec's
  institutional knowledge — do not relitigate):
  - harvester: harvest until full, deliver until empty; full + all
    sinks full → assist (upgrade).
  - upgrader: collect until full, upgrade until empty.
  - builder: gather until full; full → build if sites exist, else
    assist; never freeze, never go blind (both old bugs must be
    UNREPRESENTABLE or provably escaped in the new vocabulary).
- Shell `emitEvent` becomes a mechanical projection of the world into
  the new observation type — no policy, no priority tricks that
  reintroduce masking.
- `Memory.stats.creeps[*].event` telemetry and the flight recorder
  (`Memory.trace`, shell/main.ts) keep working — adjust their event
  field to the new encoding, and update tests/integration.nix probes
  that grep event names (telemetry contract: change together).

### Act 2 — the tower (first non-creep machine)

- Spec (`dox/creeps.dox`): tower FSM — its own state union (disjoint
  from creep states, disjointness is load-bearing for the shell's
  machine registry), observations (hostile present, damaged structure
  present, tower energy level), behaviors (attack / repair / idle) with
  tutorial-5 priority: attack hostiles over repair (reference does
  repair-then-attack per tick; decide and DOCUMENT the order in the
  spec). Population/placement policy for the tower (desiredTowers=1,
  placement offsets like extensionOffsets) is brain data.
- Sink vocabulary: tower joins spawn/extension as an energy sink for
  delivery (reference role.harvester.js). Decide in the spec whether
  tower energy participates in sink-saturation observations and at what
  threshold (a tower burning energy on repairs is a leaky sink — don't
  let it deadlock "saturated" semantics).
- Shell (`shell/main.ts`): observe towers + hostiles + damaged
  structures (FIND_HOSTILE_CREEPS, hits < hitsMax), feed the tower
  machine, execute tower.attack/tower.repair; extend TargetKind
  resolution (hostile, damagedStructure). Tower is a structure, not a
  creep: no TTL, no spawn — the generic interpreter loop may need a
  second machine-driving loop over owned towers. Zero policy in the
  shell, same as ever.

### Act 3 — itest (RCL3 + hostile, CLI world surgery)

- Force RCL 3: raise controller level/progress via the server CLI
  (`storage.db['rooms.objects'].update` on the controller) rather than
  grinding — itest wall-clock stays sane.
- Place/verify tower: spec-driven construction site once RCL 3 allows
  it; probe `Memory.stats` for towersBuilt / tower energy (extend the
  telemetry contract; change stats + probes together).
- Spawn a hostile: seed world has the `Invader` NPC user (uid '2');
  insert an invader creep into the room via
  `storage.db['rooms.objects'].insert` (or the server's invader
  machinery if exposed). Probe: hostile object disappears (killed),
  colony roleCounts recover, damaged-structure hits restored.
- Existing probes (turnover heartbeat, sinksFull, extension) stay
  green through the vocabulary reform.

## Diagnostics available (use them, they were built for this)

- Live CLI from host: VM forwards 21026;
  `(printf 'CMD\n'; sleep 3) | nc -N -w 6 127.0.0.1 21026`.
  Memory: `storage.env.get('memory:<uid>').then(m=>JSON.parse(m).stats)`
  (Promise). lambdafan uid via
  `storage.db.users.find({username:'lambdafan'})`. VM console pane is
  the server's stdout — never `run-vm.sh send` shell commands into it.
- `Memory.trace` flight recorder (shell/main.ts): per-creep
  (tick, event, fsm, action, rc) ring buffer, change-only entries.
  `action` with `rc: null` = resolved no target = the freeze signature.
- Stock world seed: simplebot NPCs (MichaelBot W9N9 — lambdafan's
  W9N8 neighbor — EmmaBot, AliceBot, JackBot) reborn on every
  reset-local. Foreign creeps in-room are PLAUSIBLE — a free live
  test source for hostile observations, and a known confounder.

## Constraints

- Brain/hands split is law. Vocabulary, FSMs, priorities, thresholds,
  placement → dox/creeps.dox (spec-author agent). API calls,
  observation projection → shell/main.ts (shell-hands agent).
  tutorial-porter for reference analysis; nix-pipeline/server-doctor
  as needed.
- `Memory.stats` is the itest telemetry contract — change stats and
  tests/integration.nix probes together.
- Never hand-edit generated/ or vendor/; `nix run .#generate`
  refreshes them. Never weaken a checker.
- Cheap checks freely (`paradox check --path dox`, typecheck build).
  `.#itest` boots a VM — ask the user. Deploys to the user's running
  world: user runs them (established preference).
- Spec fix already on this branch (builder storeFull escape) is prior
  art — build on it, don't revert it.

## Result

- One observation vocabulary, masking-proof, with tower observations
  first-class — the event contract the evolution tournament inherits.
- Tower built, fed, defending: tutorial 5 complete = the tutorial
  platform DONE, post-tutorial game unlocked.
- Itest proves the whole story end-to-end: RCL3 → tower → invader dead
  → repairs → economy heartbeat unbroken.

## Files

`dox/creeps.dox`, `shell/main.ts`, `shell/memory.d.ts`,
`tests/integration.nix`, generated/ + vendor/ (build outputs). Flake
only if telemetry/probe wiring demands it.
