## The Postscript

Setup for every exercise: download this post's installer ISO
<!-- TODO: Hetzner release link, pinned at release time -->, install and
boot it as in post zero, and inside the VM:

```
cd ~/dox-populi
git checkout 2-tutorial-two
```

Objective 1 was what a generic interpreter buys.

**Exercise 1.** Grep `shell/main.ts` for `harvester`, `upgrader`,
`builder`. Then find where each role's behavior lives in `dox/creeps.dox`.

**Exercise 2.** Read `docs/session-prompt-tutorial-3.md` — the orders that
started this session, success criterion included: adding a role touches
the harness only where a new primitive enters the vocabulary. Check each
criterion against this post's evidence — find where the post shows it, or
fails to.

Objective 2 was the refactor that deletes post one's fix.

**Exercise 3.** Read post one's ERR_FULL fix on `1-tutorial-one`
(`shell/main.ts`, the delivering case). Come back to this branch and find
what replaced it. Explain to yourself why the deadlock has nowhere left
to happen — then check your answer against the transition functions in
`generated/`.

Objective 3 was the disagreement between a tool's own subcommands.

**Exercise 4.** Read `docs/paradox-check-generate-asymmetry.md`. Run
`paradox check --path dox`, then `nix run .#generate` — watch where the
machine verification actually happens.

**Stretch.** Ask an LLM why a generic interpreter needs zero role
literals to stay generic. Verify its answer against the `Action` and
`TargetKind` switches in `shell/main.ts`.

The lesson: the test that forced post one's fix into existence blessed
its removal — the same battery, green on both sides of the deletion.

Before the next post: the extension your builder raised stores energy the
spawn has yet to spend — every role still wears the same three-part body.
Find `workerBody` in the spec and count what it costs. Post three spends
the budget.

**The assignment.** These are the orders I gave the LLM for the next
session, kept word for word. Run them yourself: same VM, your own agent,
starting from the branch you're on — where the orders say "from main,"
stay on `2-tutorial-two`. The next post shows my session. Bring yours.

```
# Session prompt: Tutorial three — auto-spawning, and the colony survives its own deaths

Branch: create `3-tutorial-three` from main. Reference:
`~/github/tutorial-scripts/section4/` (main.js, role.harvester.js,
role.upgrader.js). Full evolutionary context: `docs/evolution-plan.md`
(this session is still Phase 0).

FRAMING — read this first: section 4 is the tutorial's "auto-spawning"
chapter, and this project has auto-spawned since tutorial one: memory
cleanup and spawnQueue-driven population are already spec policy. A
naive port is a no-op — which is exactly the trap. Section 4's real
subject is population TURNOVER: the colony as an organism that outlives
its cells. Nothing in the pipeline yet proves a death→respawn cycle;
creeps have simply never lived long enough in a test to die. And
tutorial two left a debt: extensions raised energy capacity that the
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
```
