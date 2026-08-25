# Blog post four — outline

**Title:** Verified and Wrong
**Branch:** `7-tutorial-5`
**Source transcript:** `docs/unedited/one/2026-07-31-local-command-caveat*.txt`
(draft-time note: `2026-08-02-local-command-caveat*` appears to be a duplicate capture
of the same session — verify before quoting from it)
**Source artifacts:** `docs/session-prompt-tutorial-5.md`

## 1. The Promise

- The setup: tutorial 5 is defense — a tower that shoots invaders. The
  tower gets its decision logic from the same spec as the creeps. Every
  check passes. And the colony freezes anyway.
- What you'll learn:
  1. The spec works for more than creeps — the tower gets an FSM from
     the same spec, same pipeline, and what `paradox check` verifies
     about it: the machine is consistent and total.
  2. Every gate can pass while the spec encodes the wrong policy.
     Paradox verifies the machine is consistent and total; only the
     human can verify the policy is the one the colony needs. That
     division of labor is the design, and this post shows both halves
     doing their jobs.
  3. How telemetry turns a live world into a debuggable one — per-creep
     `{role, event, fsm, action}` in `Memory.stats`, read straight off
     the running server.
- Jargon links out on first use: totality, telemetry.

## 2. The Session

Candidate receipts (line numbers into the transcript; verify every
quote at draft time). Author's questions in bold.

- Setup, brief: the tower FSM ports in — three states (attacking,
  repairing, watching), three events with explicit priority
  (sawHostile > sawDamage > quiet). Paradox rejects a one-field
  product type (~609–686); a field is added; Paradox signs off. Tools
  bite, the loop absorbs it — two sentences.
- The RCL-surgery itest saga, summarized: the defense test times out
  (~1831), a second failure shows the surgery itself never took
  (~2093), root cause: the storage module rejects MongoDB `$set` —
  fix is find-modify-update, plus a verification probe so the failure
  can never again be silent (~2126–2162).
- **The headline, spent whole — the live bug hunt:**
  - **~2174** — "im running tituorial 5, what behaviors can I expect"
    — the author watching the world, expectations set on record.
  - **~2217** — "what is rcl 3 mean?" — interrogation as tutoring,
    mid-session.
  - **~2237** — "upgrader-192 has stopped doing anything carrying no
    energy" → **~2262** — "the other creeps have stopped" →
    **~2284** — "i want you to investigate".
  - ~2342–2359 — the telemetry fingers both builders self-looping:
    `building + sinksFull → building`. The spec bug named: sinksFull
    masks noSites; the builder holds a full store forever.
  - Every check had passed this spec — `paradox check` had found it
    consistent.
  - ~2361–2381, ~2516–2537 — two transitions fixed with rationale in
    the spec: building + sinksFull → assisting; gathering + sinksFull
    → building.
  - **~2514** — "yes fix it and deploy" — the human as final word.
  - ~2403–2410 — generate, typecheck, fsm-behavior all green on the
    corrected spec.
- Guards context, one paragraph, cited from
  `docs/session-prompt-tutorial-5.md` as artifact: the flat event
  vocabulary was chosen after Paradox guards proved unusable for
  observations. No transcript scene exists, so none is staged —
  curation law: no quoting ghosts.

Curation notes: the live bug hunt is the whole show — a human watching
the game catches what every check blessed, and the same pipeline
that missed the bug diagnoses and fixes it. Keep the author's
escalation sequence intact; it reads like a detective story. The RCL
saga gets three sentences of itest plumbing.

## 3. The Proof

- GIF: the tower one-shotting the invader.
- Still: `Memory.stats` per-creep telemetry mid-diagnosis — the
  self-loop visible in `{role, event, fsm, action}`.
- Caption law: every capture names the command that produced it.

## 4. The Postscript

- Exercises:
  1. (objective 1) Read the tower machine in `dox/creeps.dox`. Three
     events, explicit priority. Predict: hostile in the room AND a
     damaged rampart — what does the tower do? Check against the
     generated transition functions.
  2. (objective 2) Check out the commit before the builder fix. Read
     `building + sinksFull → building` in the spec. Run
     `paradox check --path dox` and `nix run .#generate` — watch every
     gate pass on a spec that deadlocks the colony. Explain what
     `paradox check` verified.
  3. (objective 3) Boot your VM, deploy, and read
     `Memory.stats.creeps` off the running server. Find each creep's
     `{role, event, fsm, action}` and match it to the machine in the
     spec.
  4. (objective 2) Read `docs/session-prompt-tutorial-5.md` — the
     author's written orders, three acts and success criteria. Check
     each criterion against the evidence in this post — find where the
     post shows it, or fails to.
- Stretch (objective 2): ask an LLM what Z3 verifies about an FSM
  spec, then test the answer against this post's bug. The
  interrogation habit, fifth rep.
