# Blog post one — outline

**Title:** Your First Spec
**Branch:** `1-tutorial-2`
**Source transcript:** `docs/unedited/one/2026-07-30-local-command-caveat*.txt`

## 1. The Promise

- The setup: the project's decision logic moves into a spec a machine can
  check — the first FSM (harvester, upgrader), and what happened when it
  was wrong.
- What you'll learn:
  1. Where decision logic lives — the spec, and why the harness holds
     none of it.
  2. How the code-test loop turns a behavior bug into a failing test.
  3. That a green test deserves interrogation as much as a red one.
- The side-by-side: the official tutorial JS next to the `.dox` spec. Same
  behavior; one of them is machine-checked. The tutorial defines correct —
  a fixed target set by someone else.
- The split, introduced through the session's own line: the decisions
  live in the spec; the harness observes and executes.
- Jargon links out on first use: finite-state machine, spec.

## 2. The Session

Candidate receipts (line numbers into the transcript; verify every quote
at draft time). Author's questions in bold.

- **~8** — "analyse the code base ... deliver tutorial 2 and then deploy.
  we will also need an integration test verifying tutorial 2 succeeded."
  The test demanded in the same breath as the feature.
- **~599** — "im watching the code in action, what was tutorial 2
  attempting to do?" → "section 1 was 'can you eat,' section 2 is 'can
  you grow.'"
- **~626 / ~682** — "the harvester isnt doing anything" → live-failure
  diagnosis begins.
- **Loop one — the spawnFull bug (headline):**
  - **~1152** — "write an integration test that tests for correct
    behavior" → test written first.
  - ~1324 — the test FAILS: `collecting + spawnFull → upgrading ...
    expected "upgrading", got "collecting"`. The bug on record before
    the fix exists.
  - ~1035–1058 — root cause: storeFull checked before spawnFull; when
    both are true the compound signal never fires; transfer() returns
    ERR_FULL forever.
  - ~1089–1122 — spec fix with inline rationale; ~1451–1453 — harness
    emitEvent rewritten as a compound condition.
  - ~1376–1389 — paradox-check, typecheck, fsm-behavior all pass:
    "Three witnesses. All passed."
- **~1514** — "why did the tests pass?" — interrogating a green result.
  Answer on record: the test covered transition functions, not
  emitEvent. The coverage gap named and closed.
- **~1529** — "dont mock them, use the game runtime" — the engine as the
  final oracle.
- **Loop two — the ERR_FULL partial-transfer deadlock (~2089–2213):**
  itest catches what the unit test could not (creep at 30/50, spawn
  full, compound condition false, creep stuck). Fix: the harness
  observes the rejected transfer and reports it to the decision logic
  as a spawnFull event.
  Regression counter `errFullRecoveries` + itest probe added so it
  cannot return unnoticed.

Curation notes: spend excerpt budget on "why did the tests pass?" — a
human interrogating a green checkmark is the learnability claim in one
frame. Loop two can be summarized in two sentences plus the fix quote;
its mechanics matter less than the fact that a different test caught
it.

## 3. The Proof

- GIF: harvester hauling to spawn, upgrader feeding the controller, the
  controller progress bar climbing.
- Caption law: every GIF names the command that produced it.

## 4. The Postscript

- Exercises:
  1. (objective 1) Read the harvester machine in `dox/creeps.dox`.
     Predict: store full AND spawn full — what happens? Check your answer
     against the generated code.
  2. (objective 2) Break it on purpose: change one transition target in
     the spec, run the checks, read what fails and how it tells you.
  3. (objective 1) Side-by-side read: the official tutorial's role code
     vs. the spec. Which one could have hidden the spawnFull bug longer?
- Stretch (objective 3): ask an LLM why spawnFull has to be a compound
  signal, then verify its answer against `emitEvent` in `shell/main.ts`.
  The interrogation habit, second rep.
- Lesson: the bug was on record in a failing test before the fix
  existed, and the fix passed paradox check, the typecheck, and
  fsm-behavior — the loop from the doctrine block, run twice, on the
  record.
