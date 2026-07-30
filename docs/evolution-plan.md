# Evolution plan: the Darwin arena

Phased plan for turning the completed-tutorial platform into an
evolutionary tournament: competing creep-team organisms, hybrid-mutated
strategies, N generations, champion assessed by fitness and delivered as
a checkable `.dox` spec.

**Not Conway.** Conway's Game of Life is a fixed-rule cellular automaton;
nothing mutates. This is a genetic algorithm with Screeps as the fitness
arena and the checkers (Paradox + Z3, `tsc --strict`) as the viability
gate.

## Design decisions (settled)

- **Genotype = the spec.** Strategies live entirely in `dox/creeps.dox`
  genomes; the shell is fixed embodiment. The brain/hands split is what
  makes "the mutator only writes correct `.dox`" a sufficient job
  description.
- **Hybrid mutator** (punctuated equilibrium / memetic algorithm):
  - *Inner loop (common, cheap):* deterministic operators over a bounded
    genome — point-mutate constants, swap transition targets, add/drop
    body parts, crossover of transition tables. No LLM calls.
  - *Outer loop (rare, expensive):* LLM macro-mutations, invoked only on
    fitness plateau. Structural moves: new states, new roles, new genes —
    extends the genome schema itself, then hands local search back to the
    dice. The LLM proposes M *deliberately divergent* variants; fitness
    disposes.
- **Claude Code / opencode is the human cockpit; headless invocations
  are the outer-loop mutator.** The human starts and steers the run from
  an interactive agent session, but the orchestrator performs
  macro-mutations by invoking the agent CLI headless (`claude -p` /
  `opencode run`) through a file-based LLM-integration protocol
  (Phase 5). In-loop LLM usage is budgeted, sandboxed, and gated — never
  conversational.
- **Disk is the source of truth, never the conversation.** Agent
  sessions end and context compresses; a run must survive both. Every
  piece of loop state (archive, schema, genomes, autopsies) lives in
  files, and every orchestrator operation is a resumable, idempotent
  step. Any fresh session must be able to pick up a run cold from the
  repo + archive alone.
- **Checkers gate both tiers identically.** A mutant is viable iff
  `paradox check` (with Z3 obligations) passes and the generated TS
  typechecks against the frozen shell. Non-viable mutants die before
  costing server time ("embryonic lethality screen").
- **Fixed embodiment boundary.** Evolution composes FSMs over a fixed
  event × action vocabulary. New sensors/actions are shell changes —
  human-gated, made rarely and deliberately, never by the mutator.

## Phase 0 — Combat vocabulary (existing roadmap)

Port tutorial sections 3–5 (branches `1-tutorial-3` … `1-tutorial-5`,
reference: `~/github/tutorial-scripts`).

- Builder role (already stubbed in `CreepRole`), extensions,
  construction; towers/defense; combat bodies (`attack`, `tough`,
  `ranged_attack`, `heal`) and hostile-response FSMs.
- Without this, "competition" is two organisms harvesting politely in
  separate rooms. The strategy space needs teeth before evolution is
  worth running.

Exit: tutorial 5 itest green.

## Phase 1 — Generic-interpreter shell (fixed embodiment)

The current shell hardcodes role/state → action wiring
(`shell/main.ts` switches on `"harvester"`/`"upgrader"` states). A
mutant introducing a novel state would no-op. Refactor:

- Spec side: `union Action` (harvestClosest, deliverToSpawn,
  upgradeController, buildNearest, attackNearestHostile, fleeToSpawn,
  idle, …); extend `CreepEvent` with the full observation vocabulary
  (hostileNear, underAttack, sitePresent, …). Each FSM state carries an
  `Action` tag.
- Shell side: one generic loop — observe (fixed `emitEvent` logic) →
  generated transition → execute by `Action` tag. Exactly one switch in
  the shell, over `Action`. No role-specific code paths.
- Extend `Memory.stats` (per-creep action, per-organism aggregates) and
  the itest probes in lockstep (telemetry contract rule).

Exit: spec-check, typecheck, itest green; adding a new state to a
machine in the spec requires zero shell edits.

## Phase 2 — Genome schema + renderer

- `schema.json` (versioned): gene kinds — bounded integers (population
  targets), body multisets under an energy-cost cap, transition tables
  over states × events, action tags over the fixed `Action` vocabulary,
  machine/role set.
- `genome.json` instances; deterministic schema-driven renderer
  genome → `creeps.dox` (`nix run .#render-genome`). Schema-driven is
  load-bearing: outer-loop schema extensions must render without
  touching the renderer, or the hybrid puts a human back in the loop.
- Add Z3 obligations to spec-check: transition totality (every
  state × event pair handled — no soft-locked creeps), body cost ≤ cap,
  no orphan states, valid initial state. This makes "correct `.dox`"
  behavioral, not just syntactic.

Exit: round-trip — genome-0 renders to a spec equivalent to the current
hand-written champion (modulo comments), and the full pipeline
(check → generate → typecheck → bundle) passes on rendered output.

## Phase 3 — Multi-organism deploy

- Generalize `deploy-local` → `deploy-many`: N accounts
  (screepsmod-auth self-provisioning already works per-account), one
  bundle per organism, spawn placement reusing the db.json
  unowned-controller scan.
- Room assignment policy: **isolated mode** (organisms far apart; clean
  parallel fitness) and **bordered mode** (shared exits; real
  interference) as an explicit parameter.
- Generation boundary: `reset-local`. Tick-rate control via the CLI
  port (21026, `system.setTickDuration`) to compress wall-clock time.

Exit: itest variant boots the server, deploys 2 organisms, both harvest
and upgrade independently, per-account telemetry readable.

## Phase 4 — Fitness harness + orchestrator (inner loop only)

- Scorer: after T ticks, poll each account's `Memory.stats`
  (`controllerProgress` primary; `spawnEnergy`, creep-ticks survived;
  combat metrics later). One number per organism per trial.
- Orchestrator (`nix run .#evolve`): per generation —
  select (elitism + tournament) → crossover + point mutations →
  render → check-filter (population as parallel nix derivations; the
  cache makes surviving elites free) → `deploy-many` → run T ticks →
  score → archive.
- Archive: append-only JSONL of (genome hash, genome, schema version,
  score, telemetry summary). The archive IS the assessment artifact.

Exit: 10 generations in isolated mode complete unattended; fitness
curve visible in the archive; champion beats genome-0.

## Phase 5 — LLM macro-mutator (outer loop): the integration protocol

- Plateau detector over the archive (best-score improvement < ε across
  K generations, or diversity collapse).
- **Headless invocation.** On plateau, the orchestrator spawns the agent
  CLI headless — `claude -p <prompt> --output-format json` or
  `opencode run` — with: working dir = a sandboxed intervention
  directory (not the live tree); tool permissions scoped to that
  directory plus the check pipeline (`paradox check`, render, `tsc`);
  hard budgets (max turns, wall-clock timeout, bounded retries).
- **File-based request/response contract** (disk is truth; processes
  and sessions both die):

  ```
  evolution/interventions/<gen>-<attempt>/
    request/
      champion.genome.json     # current best, content-hashed
      champion.dox             # rendered spec
      schema.json              # current genome schema, versioned
      fitness-history.jsonl    # the plateau evidence
      autopsy.json             # dwell times, energy stalls, rival stats
      directive.json           # M variants, diversity axes, constraints
    response/
      variant-<k>/
        schema.json            # version strictly +1
        seeds/*.genome.json    # conform to their own emitted schema
        rationale.md
    transcript.json            # agent session log — provenance/lineage
  ```

- **Trust boundary = the viability gate, never the agent.** Responses
  are parsed with refinement-typed decoders, then every variant runs
  the same pipeline as the dice: render → `paradox check` + Z3
  obligations → `tsc` against the frozen shell. Contract: ≥1 viable
  variant; else bounded retry with the failure report appended to the
  next prompt; else halt and surface to the interactive cockpit
  session. Agent output is hypothesis; the gate makes it fact.
- Schema hygiene: version bump per extension; prune genes frozen at
  default across the population for J generations (counters schema
  bloat).

Exit: one full intervention cycle end-to-end via headless invocation;
post-intervention lineage exceeds the plateau it was called to break.

## Orchestrator implementation (Phases 4–5)

- **Language: plain Haskell.** Formal verification of the orchestrator
  was considered and rejected:
  - *F* — factual non-starter: F* does not verify Haskell source; it is
    its own language extracting to OCaml/F#/C (toolchain fork).
  - *LiquidHaskell* — rejected on value: the architecture already gates
    every artifact the orchestrator produces (render → paradox check +
    Z3 → tsc), so orchestrator bugs either die at the gate or are
    visible in recomputable scores. The remaining refinement-shaped
    properties are trivial (bounded counters, append-only-by-
    construction), and the one hard property (crash-resume idempotence)
    is an IO property refinements cannot reach. Deferring is safe: LH
    is additive annotations, not a rewrite, if the kernel ever earns it.
- **Verification strategy instead:**
  - strong types doing the free work: `NonEmpty` populations, newtypes,
    smart constructors; schema versions ordered by type;
  - QuickCheck/Hedgehog property tests on the pure kernel: elitism
    monotone, selection size-preserving and total, plateau predicate
    matches its spec;
  - **`evolve audit`** — runtime verification over the archive: replay
    the real run and assert best-so-far monotone, generation indices
    dense and increasing, lineage closure, scores recomputable from
    archived telemetry. Audits the actual run (IO included), which
    static proof of the pure kernel cannot.
- **Functional core / imperative shell** — the brain/hands rule applied
  to the orchestrator itself. A pure kernel decides (selection, plateau
  detection, archive transitions, protocol FSM); a thin IO shell
  executes (process spawning, file IO, HTTP polls). Resumability by
  construction: content-hash keys, append-only archive, idempotent
  steps.
- Packaged in the flake; kernel property tests run as a build-time
  check, same standing as spec-check and typecheck: never weakened to
  make a build pass.

## Phase 6 — Coevolution + assessment

- Bordered mode with combat scoring (kills, damage, rooms held).
- Noise discipline: repeated trials per pairing; before declaring a
  plateau, re-score champions in the isolated benchmark arena (an
  arms-race stalemate is not an optimum).
- Hall of fame: past champions as sparring partners to prevent strategy
  cycling.
- Final assessment report: champion `.dox` (human-checkable, Z3/tsc
  verified), fitness curve, lineage of structural interventions.

## Known failure modes

| Risk | Mitigation |
|---|---|
| LLM intervention collapses diversity (writes "the" answer) | Demand M divergent structural bets; fitness selects |
| Schema bloat starves the inner loop | Gene pruning; more evals per gen after extensions |
| Fake plateaus from coevolution noise | Repeated trials; isolated-arena benchmark before declaring stasis |
| Renderer hardcodes schema | Renderer is schema-driven from day one (Phase 2 exit criterion) |
| Fitness overfits one map | Rotate/benchmark maps; score across trials |

## Standing rules (unchanged)

- Never weaken a checker to make a mutant pass — fix the schema or the
  shell vocabulary.
- `Memory.stats` and the itest probes change together.
- Expensive checks (`nix flake check`, `.#itest`) and anything touching
  live screeps.com stay explicitly user-gated; the evolve loop runs
  against the local server only.
