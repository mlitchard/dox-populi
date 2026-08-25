# Blog post three — outline

**Title:** Bodies, Budgets, and the Literal Bridge
**Branch:** `4-tutorial-4`
**Source transcript:** `docs/unedited/one/2026-07-30-session-prompt-tutorial-4-*.txt`
**Source artifacts:** `docs/session-prompt-tutorial-4.md`,
`dox/creeps.dox` + `shell/main.ts` (the literal bridge itself)

## 1. The Promise

- The setup: tutorial 4 gives creeps bigger bodies — and bigger bodies
  cost energy the colony may not have. The spec grows a tier list; the
  colony learns to die and come back.
- What you'll learn:
  1. How the spec ranks and the world disposes — tiered bodies,
     richest-first, and why affording against energy on hand instead
     of capacity is the difference between recovery and deadlock.
  2. The literal bridge: union variant names chosen to match Screeps'
     own strings, so a misspelled variant is a compile error and the
     harness uses the spec's word directly as the API key.
  3. How you test that a colony outlives its creeps — an integration
     test that waits for a natural death and demands recovery.
- Jargon links out on first use: union type, string literal type.

## 2. The Session

The design work happened inside collapsed agent runs; what's on the
record is the author's interrogations and the contracts they forced
into the open. Curation law: **no quoting ghosts** — the literal
bridge is told from the code, cited as code, because no transcript
scene exists for it.

Candidate receipts (line numbers into the transcript; verify every
quote at draft time). Author's questions in bold.

- **~136** — "did you write integration tests verifying new tutorial 4
  spec?" → the five-phase generational itest contract on record
  (~143–166): deaths >= 1, baseline controllerProgress at death,
  recovery to full roleCounts with births >= deaths + 5, a live
  5-part creep showing the extension finally gets spent, and progress
  strictly above the baseline after the funeral.
- ~296–310 — the afford-basis rationale: afford against energy on
  hand — wait-for-capacity is a deadlock: all
  harvesters die, the extension never refills, 350 never arrives, and
  the spawn waits on a promise no one's alive to keep.
- ~168–177 — the assistant flags a bug hiding inside the green:
  run-vm.sh fails silently on first run and boots a blank disk on the
  second → **"fix run-vm.sh"**.
- **~366** — "do i what i told you to do, do not deviate from my
  instructions" — the human as final word, disciplining agent
  initiative.
- **~396** — "i included the bug fix in this commit, note my sin." —
  the author holds himself to the same standard, on the record.
- **~416** — "i already ran it" — the itest run executed by the human;
  the loop doesn't wait for the assistant.
- The literal bridge, told from the artifacts: the body-part union in
  `dox/creeps.dox` next to the harness code that uses those variant
  names directly as Screeps API keys. A variant outside Screeps' own
  strings fails to compile; a typo in the spec is a compile error in
  the harness.

Curation notes: the itest contract is the headline — five phases that
turn "the colony survives" from a feeling into a checkable claim. The
afford-basis rationale is the best teaching moment; quote it whole.
The commit confession is short and humanizing; keep it.

## 3. The Proof

- GIF: a creep dies of old age; the spawn answers with a 5-part heavy
  worker; roleCounts refill to 2/1/2.
- Still: `Memory.stats` showing births and deaths both climbing while
  controllerProgress rises.
- Caption law: every capture names the command that produced it.

## 4. The Postscript

- Exercises:
  1. (objective 1) Find the body tiers in `dox/creeps.dox`. Predict:
     spawn at 300 energy, extension empty — which body spawns? Now
     predict the same moment if affordability were checked against
     energyCapacityAvailable instead. Which colony recovers?
  2. (objective 2) Pick one body-part variant in the spec and misspell
     it. Run `nix run .#generate` and the typecheck — read where the
     error surfaces and what it says. Restore it.
  3. (objective 3) Read the generational subtest in
     `tests/integration.nix`. Map each of its five phases to the claim
     it checks. Which phase would a colony that never spawns heavy
     workers fail?
  4. (objective 1) Read `docs/session-prompt-tutorial-4.md` — the
     author's written orders to the LLM, three phases: port audit,
     capacity-tiered bodies, turnover proof. Check each phase against
     the evidence in this post — find where the post shows it, or
     fails to.
- Stretch (objective 2): ask an LLM why the union variant names had to
  match Screeps' property strings exactly, then verify its answer
  against the harness code that consumes them. The interrogation
  habit, fourth rep.
