# A Machine That Argues With Itself Until the Truth Falls Out

*A narrative extracted from the raw session transcripts in `docs/unedited/`
(2026-07-26 through 2026-07-31). Five threads, one story: how the code was
made, how it was proven, how the loop that made it was itself made faster —
and what that implies about where the productive power actually comes from.*

---

## Thread 1 — The Loop: attempt, witness, verdict, ledger

Every session in the transcripts runs the same liturgy, and the tapes prove
it was enforced, not aspirational:

**Attempt → checker → feedback → fix → checker again → commit.**

The canonical specimen is the **spawnFull bug** (2026-07-30, tutorial 2).
Live symptom: a harvester frozen at the source with a full store. Diagnosis:
an event-priority bug in `emitEvent`. But no hotfix followed. First came a
*failing test* — `tests/fsm-behavior.ts`, written to assert the transition
that should exist, run, and failing exactly as predicted (`expected
'upgrading', got 'collecting'`). Then the one-line spec fix. Then all three
checks green. Then — the part most shops skip — the fix turned out to be too
blunt (an upgrader hauling 2 energy at a time because `spawnFull` fired
every tick), and the loop ran *again*: compound condition, regenerate, three
witnesses, ship. The loop is not a happy path. It is a recursion, and it
terminates on proof, not on optimism.

The same shape appears everywhere in the corpus:

- **Tutorial 5**: Paradox rejects the tower spec ("product types require ≥2
  fields") → fold `initial` into `TowerContext` → generate passes → tsc
  passes → fsm-behavior passes. "Three witnesses, court of law."
- **VM installer**: `nix flake archive` silently dragged a `git+ssh://`
  private input toward a distributable ISO → caught, deleted, and a NOTE
  comment left as a tombstone so it never comes back.
- **Tutorial 3** (`ed20cc1`): 2,908 insertions land only after generate +
  typecheck + fsm-behavior all sign off, under a commit message that reads
  like a case summary.
- **The test-suite prosecution** (2026-07-31): the loop turned *inward* —
  the suite itself indicted on six counts (fsm-behavior checked `.target`
  but never `.action`; the itest invader was a scarecrow; a headline probe
  that maybe could not fail), with evidence fetched from the upstream
  Screeps engine source to secure the conviction.

The commits are part of the loop: each one a ledger entry recording the
*why*, down to the "commit contamination" confession (an unrelated
`run-vm.sh` fix mixed into the tutorial-4 commit) being formally noted and
absolved — "venial, not mortal."

## Thread 2 — Manual testing: the human is a sensor the checkers don't have

The uncomfortable truth the tapes force into view: **the checkers never
caught a single behavioral bug in the live world. The human caught all of
them.**

- Harvester stuck at the source → human watching the game client.
- Upgrader carrying 2 energy per trip → human watching the game client.
- `run-vm.sh` dying silently at an ISO glob, then booting a blank 40G disk
  on the second run → human running the script twice.
- The stuck builder freezing until TTL death (births 105 / deaths 100) →
  human live-debugging over `nc` to the server CLI on port 21026, reading
  `Memory.stats` like a flight recorder.
- The wrong Steam path, the stale SSH host key, the ssh-less ISO → human at
  the console.

But manual observation never *stayed* manual. Every field bug was converted
into machinery: the stuck harvester became `fsm-behavior.ts`; the
transient-poll weakness became the `Memory.trace` flight recorder; the
`run-vm.sh` death became an ordering fix (resolve the ISO *before* creating
the disk) plus a syntax check. **Manual testing is the discovery organ; the
checkers are the memory.** The human finds it once; the pipeline refuses to
forget it.

The human also rationed the expensive checks. Over and over the assistant
reaches for a dry-run or an itest and is interrupted — "i already ran it."
Cheap checks run freely; the VM boot is lit only on explicit authority ("I
don't light that on my own authority. Say the word."). That is not
friction. That is a cost model with a human in the pricing loop.

## Thread 3 — The tooling: a graduated court system

The stack is not a pile of tools; it is a hierarchy of witnesses, ordered
by cost:

| Tier | Witness | Cost | What it convicts |
|---|---|---|---|
| 1 | `paradox check` + Z3 | seconds | spec incoherence; non-total or unreachable FSMs |
| 2 | `tsc --strict` over shell + generated + vendor | seconds | the shell lying about the brain's types |
| 3 | `fsm-behavior` nix check | seconds | wrong transitions; wrong action/target wiring |
| 4 | `nix eval` / `bash -n` | seconds | derivations and scripts that cannot even parse |
| 5 | itest (QEMU VM, real server, real deploy, polls `Memory.stats`) | hours | emergent behavior — turnover, defense, recovery |
| 6 | live world + CLI over `nc 21026` + human eyes | human time | everything the tiers above cannot see |

The connective tissue matters as much as the tiers: the nix flake owns the
whole chain, so every check is reproducible; `gitlab-ci.nix` *generates* CI
from the flake, and when it generated duplicates the fix was a flake
overlay — regenerate, never hand-edit; the literal-bridge trick lets tsc
prove the shell's event strings against the generated union; the Claude
Code subagents (spec-author, shell-hands, tutorial-porter, server-doctor,
nix-pipeline) mirror the architecture's layers one-to-one. Even the
transcripts in `docs/unedited/` are tooling — the project's own black-box
recorder, from which this document was reconstructed.

Failures cascade *upward* through cheap layers instead of blindsiding at
runtime. That is the whole design.

## Thread 4 — Sharpening the loop: the dev cycle as an engineering object

The loop did not stay the same speed. Midway through the corpus, the loop
itself went on trial — three convictions, three fixes, and the cycle time
collapsed.

**1. Installer / runner conflation of concerns** (`935370f`, branch
`8-fix-dev-iso`). The original `run-vm.sh` tried to be everything: ISO
locator, disk provisioner, installer, runner — and the conflation is
exactly what produced the silent first-run death and the blank-disk second
run. The fix was a separation, enforced over three rounds of review:
`run-vm.sh` RUNS the VM, nothing else — it errors if the disk is missing.
Provisioning became a flake program: `nix run .#installer-iso` builds the
dubai-style dd-pattern installer (prebuilt disko raw image embedded in the
ISO; dd → grow → poweroff — no nixos-install, no nix, no git at install
time). And the seeded-snapshot fallback was deliberately *removed* in favor
of a live 9p mount of the host repo: the VM stopped being a stale copy of
the dev environment and became a window onto it. Edit on the host, test in
the guest, no sync step. A second script and a `run-vm.sh install`
subcommand were both rejected on principle — the flake program IS the
installer.

**2. Superfluous tests removed.** Dead verification is worse than no
verification: it costs time every cycle and testifies to nothing.

- The ERR_FULL recovery subtest and its 31 lines of shell code died in
  `ed20cc1` — not weakened, *proven unreachable*: observe-first plus
  `hasFreeEnergy`-filtered targeting means the engine clamps partial
  transfers to OK, so the recovery path could never fire. 8,000 ticks of
  itest evidence, counter at zero. The test was removed because the bug
  became impossible, and the commit says so.
- Eleven duplicate CI jobs dropped via the flake `gitlab` overlay
  (`97554a3`): the VM chain collapsed to its deepest artifact, three names
  for the same derivation reduced to one, and `flake:check` — which re-ran
  every check including the multi-hour itest — cut entirely.
- Redundant hand-pinned FSM regression tests replaced by two exhaustive
  oracle sweeps (every state × every event for transitions; every state's
  {action, target} for behavior) — less code, strictly more coverage,
  closing the `.action` hole the prosecution found.

**3. The game tick, parameterized then floored** (`c95fcca` → `43b8c47`,
branch `9-tick-speed`). The private server's tick duration became a flake
knob — `tickMs = 50` as the default, `SCREEPS_TICK_MS` as an *optional*
override, asserted over the CLI on every launch because `setTickDuration`
persists in the world's env. Against the stock one-second cadence, that is
a ~20× compression of every wall-clock-per-tick cost in the pipeline: the
itest's generational turnover proof, the `Memory.trace` polls, and every
live debugging session at the `nc` prompt. The same funeral that took
fifteen minutes of real time to observe now takes under one.

The pattern across all three: **the loop is subject to the loop.** The dev
cycle got audited with the same adversarial method as the product — find
the waste, prove it is waste, cut it, verify nothing true was lost. Faster
ticks made the expensive tier cheaper; deleted tests made every cycle
shorter; separated concerns made the VM boot deterministic. Feedback
latency is the interest rate on every experiment, and the project
refinanced.

## Thread 5 — How the code was made, and what that implies

Read the authorship ledger honestly: **the LLM wrote essentially all of
it.** The spec, the shell, the tests, the flake surgery, the VM installer,
the CI overlay, the commit messages. When the assistant was caught claiming
`creeps.dox` was hand-authored, the correction went on the record: "You got
me. Dead to rights. I wrote that file."

What did the human do? Four things — and they are the four that matter:

1. **Direction** — which tutorial section, which trade-off (afford-now vs
   afford-capacity), which door to kick.
2. **Correction** — "stop guessing"; "this is over complicated, define the
   variable in the script"; "we've been doing architecture change the whole
   time." Each correction reshaped the *method*, not just the artifact.
3. **Sensing** — the live-world observation the checkers cannot do
   (Thread 2).
4. **Authorization** — expensive checks, deploys, commits. The human holds
   the launch keys.

The checkers are the third party: the trust boundary that lets a human
safely accept thousands of lines from an author he does not line-review.
"Don't tell me it works, show me the check" is not a personality quirk; it
is the load-bearing wall of the labor arrangement.

### The implication: where the unleashed productive power comes from

- **Volume without review-paralysis.** 2,908 lines in one commit, accepted
  not because a human read every line but because Z3, tsc, and a behavior
  oracle read every line. Verification substitutes for review; the human's
  scarce attention moves from reading code to judging outcomes and pricing
  risk.
- **The bottleneck moved — twice.** It was never "can the LLM write it fast
  enough." The first bottleneck was human attention, relieved by the
  checkers. The second was feedback latency — VM boots, one-second ticks,
  dead tests — relieved by Thread 4. Human effort concentrated at the
  highest-leverage points (vocabulary design, live sensing, cost
  authorization) while the machine flooded everything else.
- **The system audits itself.** By the end of the corpus the loop had
  turned fully recursive: the LLM prosecuting its own test suite, fetching
  upstream engine source to prove one of its own probes vacuous, cutting
  its own CI duplication. A system that indicts its own verification layer
  is not a code generator. It is a quality process.
- **The endgame is explicit in the tapes.** The evolution plan
  (`docs/evolution-plan.md`) removes the human from the inner loop
  entirely: genome mutations gated by paradox/Z3/tsc, the LLM invoked only
  on fitness plateau, no keyboard in sight. The tutorial sessions were
  never about a Screeps bot. They were rehearsing the removal of every
  human touchpoint *except* direction and authorization — because the
  checkers, and a loop fast enough to trust, make the rest safe to
  delegate.

One sentence: **the productive power gets unleashed exactly when trust gets
mechanized and feedback gets cheap** — the human stops being the verifier
and becomes the judge, the checkers become the jury, the loop tightens
until an experiment costs a minute instead of an afternoon, and the machine
gets to write as fast as it can think, because every lie it might tell is
caught by something that does not sleep, does not flatter (Editor: You're absolutely right!),
and does not bill by the hour.

The user's own mid-session reframe is the thesis the whole corpus proves:

> "the old tutorial is a toy teaching kids some programming tricks. we're
> transforming that into an artifact designed to propagate state of the art
> agentic engineering practices to the same masses." (Editor: Aspirationally)

The tapes show that artifact being forged — one attempt, one witness, one
verdict, one ledger entry at a time.
