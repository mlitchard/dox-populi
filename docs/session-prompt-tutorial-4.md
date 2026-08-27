# Session prompt: Tutorial 4 — auto-spawning, and the colony survives its own deaths

Branch: create `<issue>-tutorial-4` from main. Reference:
`~/github/tutorial-scripts/section4/` (main.js, role.harvester.js,
role.upgrader.js). Full evolutionary context: `docs/evolution-plan.md`
(this session is still Phase 0).

FRAMING — read this first: section 4 is the tutorial's "auto-spawning"
chapter, and this project has auto-spawned since tutorial 2: memory
cleanup and spawnQueue-driven population are already spec policy. A
naive port is a no-op — which is exactly the trap. Section 4's real
subject is population TURNOVER: the colony as an organism that outlives
its cells. Nothing in the pipeline yet proves a death→respawn cycle;
creeps have simply never lived long enough in a test to die. And
tutorial 3 left a debt: extensions raised energy capacity that the
spawn never uses, because every role spawns the same minimal body
forever. Both are spec policy. This session makes death observable,
recovery provable, and capacity spendable.

## The work, in dependency order

1. **PORT AUDIT** (tutorial-porter): diff `section4/` against the
   current architecture and record the verdict in the session log.
   Expected findings: memory cleanup — already in the shell loop;
   population maintenance — already spawnQueue policy; the room.visual
   spawning badge — becomes telemetry, not graphics
   (`Memory.stats.spawning`: the role in production, or null). Anything
   else section 4 does that we do not — surface it before coding.

2. **CAPACITY-TIERED BODIES** (dox/creeps.dox via spec-author):
   `RoleSpec` grows from one body to an ordered list of bodies, richest
   first; body composition, tier order, and counts are spec constants.
   The shell spawns the first affordable body — mechanical maximization
   over spec data, the same pattern as `extensionOffsets` (spec ranks,
   world disposes). Decide explicitly, as a spec decision: afford
   against current `room.energyAvailable` (spawn now, small) or
   `energyCapacityAvailable` (wait for the extension to fill, spawn
   big). Either answer is policy; neither belongs in the shell.

3. **TURNOVER PROOF** (telemetry + tests/integration.nix, one
   contract): `Memory.stats` gains lifecycle telemetry — per-role live
   counts, `spawning`, and cumulative `births`/`deaths` counters
   (deaths detected in the existing memory-cleanup sweep — observation,
   not policy). The itest gains a generational probe: at compressed
   tick rate (1500-tick lifespan ≈ 150 s at 100 ms ticks) wait for a
   natural death, then assert the colony recovers — deaths ≥ 1, the
   dead role refilled to desired strength, and controllerProgress
   still rising after the funeral. That is the section-4 claim the
   tutorial never proves: unattended self-repair.

## Constraints (CLAUDE.md in full force)

- No policy, no state machines, no magic numbers in the shell. Ever.
  Body tiers, thresholds, counts: spec. The shell only executes.
- Never weaken a check to pass it — fix the spec or the shell.
- Run `nix run .#generate`, not just `paradox check`: check and
  generate disagree on machine verification
  (docs/paradox-check-generate-asymmetry.md). Generate is the real gate.
- tests/fsm-behavior.ts is a SEPARATE check (`.#checks…fsm-behavior`)
  not covered by the typecheck — if event/state vocabulary moves, it
  moves too, in the same change. It silently rotted once already.
- `paradox check` / typecheck / fsm-behavior are always fine; ask
  before `nix flake check` / `.#itest` (boots a VM).
- Agents: tutorial-porter (audit), spec-author (dox), shell-hands
  (shell), nix-pipeline (itest), server-doctor (if the world goes quiet).

## Files

`dox/creeps.dox`, `shell/main.ts`, `shell/memory.d.ts`,
`tests/integration.nix`, `tests/fsm-behavior.ts` (if vocabulary moves),
`generated/` + `vendor/` via `nix run .#generate` only.
