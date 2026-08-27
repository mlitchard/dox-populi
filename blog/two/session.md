## The Session

The transcript behind this post picks up mid-session: July 30th again,
hours after post one's, continued past a context compaction. The argument
that designed the interpreter sits on the far side of that compaction;
what survives on the record is the ending — the deletion, the commit, and
two documents the session wrote to disk. My prompts in bold, the
assistant's replies as it wrote them. Every quote is exact; the only
editing is trimming.

The record opens with the assistant filing a finding:

> On disk. docs/paradox-check-generate-asymmetry.md — symptom, mechanism
> with file:line receipts (check at Commands.hs:935 skips what generate
> runs at 830–834) …

That committed document carries the tool-gap story. From it:

> a spec that `paradox check` accepted was rejected by `paradox generate`.

> So `paradox check` applies no FSM verification whatsoever — machine
> properties are enforced only at generate time.

The workaround — per-role state unions — was already in the spec, and the
branch stood finished:

> Where we stand on the branch:
>
> - Spec, shell, fsm-behavior tests, integration.nix — all rewritten, all
>   cheap checks green: generate ✓, strict typecheck ✓, fsm-behavior ALL
>   PASSED ✓, bundle ✓.
> …
> - Not done: the itest. … And nothing's committed on 3-tutorial-3 yet.

The itest had timed out overnight. I handed over the log.

> **there was a timeout nix log
> /nix/store/7y2mlbc58f2wb05ycfbls365njg98bgs-vm-test-run-dox-populi-itest.drv**

Reading it surfaced the real question, and the assistant put it to me
directly:

> The ERR_FULL recovery subtest asserts a code path the interpreter
> refactor made unreachable (observe-first + filtered targeting means we
> never transfer to a full sink). How do we settle it?

I ruled: remove the test and the dead code. Post one's fix — the recovery
block, the `errFullRecoveries` counter, the itest subtest guarding it —
all of it came out, along with every comment still describing recovery:

> Now the testimony corrections — comments that still preach the old
> gospel of recovery when the new covenant is prevention.

The comment that replaced them, in `tests/fsm-behavior.ts`:

> // Observe-first: this event fires BEFORE any doomed transfer is
> attempted,
> // which is what makes the old ERR_FULL deadlock structurally
> impossible.

> **give me a commit message for the work just done**

> Events: storeEmpty > sinksFull > storeFull > sawSite|noSites. sinksFull
> observes sink fullness BEFORE acting, making the tutorial-2 ERR_FULL
> partial-transfer deadlock structurally impossible — the recovery block,
> errFullRecoveries telemetry, and its itest subtest are removed as dead.

> **commit it**

> ed20cc1 — sealed, tree clean, transcript filed where transcripts
> belong.

> All cheap checks were green before the seal: generate ✓, strict
> typecheck ✓, fsm-behavior ALL PASSED ✓.

The assistant pressed for the one proof still outstanding:

> One charge still pending, and you know which one: the extension probe
> never testified. … Say "run the itest" and we finish the trial.

> **i already ran the test**

I had run it myself while the assistant was still arguing about it.
