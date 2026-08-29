# First Blood

## The Promise

The colony gets an enemy. The raider's decision logic comes off the
same pipeline as everything else in this series — a
[Paradox](https://gitlab.com/paradox_labs/paradox) spec, checked,
generated, typechecked — and it lives on the server as an
[NPC](https://en.wikipedia.org/wiki/Non-player_character) user. Then
the war has to be tested, and testing it takes two sessions of the
author cross-examining his own tests and his own laws.

What you'll learn:

1. How to find where the enemy's decisions live: the raider's decision
   logic is a spec (`dox/invader/`), built by the same pipeline as the
   colony's, and seeded into the server as a dedicated NPC user —
   including the engine quirk that forced that user into existence.
2. How to size a test's claim to the evidence the world produced — and
   how to make the world produce more: the escalating-wave protocol,
   n raiders, then n+1, until damage happens.
3. How to catch two of your own rulings deadlocking, and how to amend
   a law under evidence: the tower stalls at 990 energy with every
   creep obeying, and both amendments — the refill law and the
   no-surgery doctrine — come from the author.

The code this post cites lives on branch `4-tutorial-four`.
