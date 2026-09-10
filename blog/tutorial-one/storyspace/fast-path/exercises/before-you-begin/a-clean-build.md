# This Is a Clean Build

Where the evidence lived: what you know you did. From
`docs/unedited/2026-07-30-100641-local-command-caveatcaveat-the-messages-below-w.txt`,
around line 749.

A harvester was stuck, and the agent had a theory built on a name:

> That name tells the story. harvester-1787 — spawned at game tick
> 1787. That's from the old deploy, before our code changes. It was
> created with { role: "harvester" } and no fsm field.
>
> … Try killing it. Reset the world so the new code spawns fresh
> creeps with proper memory:
>
> nix run .#reset-local

**standing at source with full store**

> That's the smoking gun. … The fact that it's standing still means
> something is erroring out silently.

**this is a clean build**

> Right, no stale creeps — this is all new code. That rules out my
> old-memory theory.

The old-deploy theory was reasoning from a creep's name. I knew my
own workflow: every run starts from a wiped world, so there was no
old deploy for the creep to be from. With that theory dead, I pasted
the deployed bundle from the client, and the real bug surfaced in
`emitEvent` — where [Why Did the Tests
Pass?](why-did-the-tests-pass.md) picks up the story.
