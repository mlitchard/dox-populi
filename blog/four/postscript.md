# First Blood

## The Postscript

Exercises, grouped by objective. Check out `4-tutorial-four` first.

**Objective 1 — find where the enemy's decisions live.**

1. Read the raider machine in `dox/invader/invader.dox`. Then grep
   `shell/` for raider decision logic and find where the raider's
   choices actually live. Find the `raiders` user and the uid-2 stub
   in the seed step in `flake.nix`.

**Objective 2 — size a test's claim to the evidence.**

2. Read the first-blood probe in `tests/integration.nix`. State
   exactly what `damageTaken >= 1` shows. State what it leaves open.
3. Read `docs/session-prompt-raider-offense.md` and
   `docs/session-prompt-live-invader.md` — the author's written orders
   for the two sessions. Check each success criterion against the
   evidence in this post: find where the post shows it, or where it
   fails to.

**Objective 3 — catch your own rulings colliding.**

4. Reconstruct the deadlock from the two laws: the latch closes at
   1000 and reopens below 500; the raid gate demands 1000. Walk the
   tower from full to 990 and explain why no creep ever feeds it
   again. Then read the sink-below-full law that replaced it in
   `dox/creeps.dox`.

Stretch (objective 3): ask an LLM how a set of individually reasonable
rules can jointly deadlock, then verify its answer against the two
laws in this post.
