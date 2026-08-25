## The Postscript

Setup for every exercise: download this post's installer ISO
<!-- TODO: Hetzner release link, pinned at release time -->, install and
boot it as in post zero, and inside the VM:

```
cd ~/dox-populi
git checkout 1-tutorial-one
```

Objective 1 was where the decisions live.

**Exercise 1.** Read the harvester machine in `dox/creeps.dox`. The
creep's store is full and the spawn is full — predict what the creep does
next. Check your prediction against the harvester's transition function
in `generated/index.ts`.

**Exercise 2.** Read the official tutorial's harvester code, then the
spec's machine, side by side. Which one could have hidden the spawnFull
bug longer?

Objective 2 was the code-test loop.

**Exercise 3.** Break it on purpose: change one transition target in
`dox/creeps.dox`, then run the checks the session ran:

```
nix build .#checks.x86_64-linux.paradox-check \
  .#checks.x86_64-linux.typecheck \
  .#checks.x86_64-linux.fsm-behavior
```

Read what fails and how it tells you.

Objective 3 was interrogating a green test.

**Stretch.** Ask an LLM why spawnFull has to be a compound signal. Verify
its answer against `emitEvent` in `shell/main.ts`.

The lesson: the bug was on record in a failing test before the fix
existed, and the fix passed paradox check, the typecheck, and
fsm-behavior — the loop, run twice, on the record.

Before the next post: read `shell/main.ts` and mark every place the
harness decides something on its own. Post two takes them away; bring
your list.
