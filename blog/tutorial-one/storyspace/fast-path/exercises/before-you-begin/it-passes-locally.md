# It Passes Locally

Where the evidence lived: CI. From
`docs/unedited/2026-07-30-100641-local-command-caveatcaveat-the-messages-below-w.txt`,
around lines 1717 and 2066.

The compound-condition fix from
[why-did-the-tests-pass.md](why-did-the-tests-pass.md) went in, with
a new integration test behind it:

> Two layers of tests:
>
> 1. fsm-behavior (pure Node, no runtime) — proves the transition
> functions produce correct states for all events.
> 2. itest (VM + real Screeps server) — new subtest polls
> Memory.stats.creeps until a harvester has event: "spawnFull" and
> fsm: "harvesting". This proves the compound event logic works in
> the actual game runtime, not just in theory.

**we have a problem upstream a failed itest from their gitlab runner.
this test passes locally**

The job log ended:

```
Exception: timed out waiting for harvester spawnFull event
```

> The log tells the whole story. …
>
> 1. Harvester delivers to spawn. Spawn had ~280/300 energy, creep
> had 50. transfer() moves 20 energy (all the spawn can hold), creep
> retains 30.
> 2. Spawn is now 300/300 (full). Creep has 30/50 (partial).
> 3. emitEvent: storeFull = false. The compound condition storeFull
> && spawnFull is false.
> 4. Returns "tick". FSM: delivering + tick → delivering.
> 5. transfer() → ERR_FULL. Nothing happens. Stuck forever.

"Works in the actual game runtime" had been checked in one world —
mine. CI ran a world with different timing, reached the partial
transfer my runs missed, and the deadlock surfaced. The claim fell to
evidence neither of us was holding.
