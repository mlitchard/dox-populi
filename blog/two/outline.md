# Blog post two — outline

**Title:** The Harness Knows Nothing, Jon Snow
**Branch:** `3-tutorial-3`
**Source transcript:** `docs/unedited/one/2026-07-30-this-session-*.txt`
**Source artifacts:** `docs/session-prompt-tutorial-3.md`,
`docs/paradox-check-generate-asymmetry.md`

## 1. The Promise

- The setup: the builder role arrives, and with it the harness stops
  knowing anything — zero role literals, zero state literals, every
  decision moved into the spec. The title is a falsifiable claim: grep
  the harness for a role name, find nothing.
- What you'll learn:
  1. Why a harness that knows nothing is worth having — what a generic
     FSM interpreter buys when the next role arrives.
  2. Architecture can delete code: post one's ERR_FULL recovery fix —
     removed because the interpreter made the deadlock structurally
     impossible.
  3. Tools have gaps: `paradox check` and `paradox generate` disagree
     on Machine verification scope — a spec can pass one and fail the
     other. The method survives because the full battery runs, so one
     subcommand's blind spot never becomes the project's blind spot;
     another gate catches it.
- Jargon links out on first use: interpreter, string literal.

## 2. The Session

This session's design argument happened off the record; what survives
is sparse dialogue plus two committed documents. Curation law: **no
quoting ghosts** — nothing appears as conversation unless it's in the
transcript; artifacts are cited as artifacts.

Candidate receipts (line numbers into the transcript; verify every
quote at draft time). Author's questions in bold.

- **The removal ruling (~47–51):** post one's ERR_FULL recovery — the
  fix a failing itest forced into existence — is deleted. The
  interpreter observes state before acting, so the deadlock cannot be
  expressed. The bug's fix dies with the bug.
- ~55–100 — fsm-behavior ALL PASSED after the deletion. The same test
  blesses the removal the way it blessed the addition.
- **~378** — "i already ran the test" — the human running the checks
  himself; the loop doesn't wait for the assistant.
- ~348–374 — the commit sealed.
- The check-vs-generate asymmetry, told from
  `docs/paradox-check-generate-asymmetry.md` (committed, 74 lines):
  `paradox generate` runs machine verification that `paradox check`
  skips; workaround = per-role state unions. Quoted as a document —
  honest "here's where the tool bit us" material.

Curation notes: the deletion is the headline — a post that removes its
predecessor's central fix demonstrates the architecture better than
any addition could. The asymmetry doc gets one tight excerpt, not a
reprint.

## 3. The Proof

- GIF: the builder raising structures the harness has never heard of.
- Still: the grep-zero terminal — grep the harness for a role name,
  find nothing. The title, verified on camera.
- Caption law: every capture names the command that produced it.

## 4. The Postscript

- Exercises:
  1. (objective 1) Grep `shell/main.ts` for `harvester`, `upgrader`,
     `builder`. Then find where each role's behavior actually lives in
     `dox/creeps.dox`.
  2. (objective 2) Read post one's ERR_FULL fix, then find its absence
     here. Explain to yourself why the interpreter can't deadlock the
     same way — then check your answer against the transition
     functions in `generated/`.
  3. (objective 3) Read `docs/paradox-check-generate-asymmetry.md`.
     Run `paradox check --path dox`, then `nix run .#generate` — watch
     where each one's verification actually happens.
  4. (objective 1) Read `docs/session-prompt-tutorial-3.md` — the
     author's written orders to the LLM, success criterion included:
     adding a role touches the harness only where new primitives enter
     the vocabulary. Check each success criterion against the evidence
     in this post — find where the post shows it, or fails to.
- Stretch (objective 1): ask an LLM why a generic interpreter needs
  zero role literals to stay generic, then verify its answer against
  the Action and TargetKind switches in `shell/main.ts`. The
  interrogation habit, third rep.
