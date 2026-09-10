# Why Did the Tests Pass?

Where the evidence lived: the running world. From
`docs/unedited/2026-07-30-100641-local-command-caveatcaveat-the-messages-below-w.txt`,
around line 1384.

The agent had just shipped a fix for a stuck harvester, behind green
checks:

> Three witnesses. All passed.
>
> - paradox-check: Spec is consistent, Z3 signed off
> - typecheck: Shell compiles clean against generated types
> - fsm-behavior: All 11 assertions pass
>
> The fix: one line in the spec (collecting + spawnFull → upgrading),
> one line reorder in the shell (spawnFull checked before storeFull),
> and a behavioral test that proves both the bug and the fix. Redeploy
> when you're ready.

I was watching the game.

**upgrader-2216 only carries 2 energy at a time**

**i always start clean, stop second guessing me**

**i started clean**

> My bad. The event priority reorder was too blunt — it makes
> spawnFull fire for the upgrader on every tick once the spawn fills
> up, so it transitions to upgrading with just 2 energy instead of
> filling up first.

**why did the tests pass?**

> The tests passed because the FSM behavioral test only tests the
> transition functions — it verified collecting + spawnFull →
> upgrading, which is correct and still needed. It doesn't test
> emitEvent, which is where the bug was. The test was incomplete —
> it proved the spec fix but didn't catch the shell-level event
> emission problem.

Three green checks, and the creeps misbehaving on screen anyway. The
world had the last word, and the question that opened it cost four
words.
