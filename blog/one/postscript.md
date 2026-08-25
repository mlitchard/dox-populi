## The Postscript

Setup for every exercise: download this post's installer ISO
<!-- TODO: Hetzner release link, pinned at release time -->, install and
boot it as in post zero, and inside the VM:

```
cd ~/dox-populi
git checkout 2-tutorial-two
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

**The assignment.** These are the orders I gave the LLM for the next
session, kept word for word. Run them yourself: same VM, your own agent,
starting from the branch you're on — where the orders say "from main,"
stay on `2-tutorial-two`. The next post shows my session. Bring yours.

```
# Session prompt: Tutorial 3 — builder role, and the shell becomes an interpreter

Branch: create `<issue>-tutorial-3` from main. Reference:
`~/github/tutorial-scripts/section3/` (main.js, role.builder.js,
role.harvester.js). Full evolutionary context: `docs/evolution-plan.md`.

FRAMING — read this first: the tutorial is the pretext, not the product.
Section 3 is the first time the action vocabulary grows (build,
createConstructionSite, transfer targets beyond spawn). That makes it the
proving ground for the architecture this project exists to demonstrate:
when capability grows, ONLY the spec learns policy — the shell learns
vocabulary, never wiring. Today shell/main.ts hardcodes role/state→action
dispatch; a novel state from a future mutant would no-op. This session
kills that.

## The work, in dependency order

1. **INTERPRETER REFACTOR** (shell/main.ts + dox/creeps.dox emit contract):
   - Fixed event vocabulary the shell can observe (storeFull, storeEmpty,
     sawConstructionSite, spawnFull, ERR_* results, ...) and fixed action
     vocabulary it can execute (harvest, transfer, upgrade, build, moveTo,
     spawn, placeSite, idle).
   - Generated brain tags each FSM state with its action + target
     selector; the shell becomes a generic loop: observe → emit events →
     brain returns (state, action) → execute. Zero role names, zero state
     names, zero policy constants in the shell.
   - Test of success: adding the builder role (step 2) should touch the
     shell ONLY where a genuinely new primitive enters the vocabulary
     (build, placeSite) — not its dispatch logic.

2. **SECTION 3 SEMANTICS** (all in dox/creeps.dox, via spec-author):
   - Builder FSM: collecting (harvest; store full → building) ↔ building
     (build first construction site, moveTo on ERR_NOT_IN_RANGE; store
     empty → collecting). Decide explicitly: idle vs fall-back-to-upgrade
     when no sites exist — a spec decision either way.
   - Harvester delivery policy widens: (STRUCTURE_EXTENSION |
     STRUCTURE_SPAWN) with free energy capacity.
   - Population policy: harvesters + builders, counts and bodies as spec
     constants (tutorial does this by hand in the console; here it's
     policy, so it's spec).
   - Extension placement: tutorial does it manually; here deploy-local
     places Spawn1 already — extension site placement policy (where/when/
     how many) is spec; the shell/deploy only executes placeSite.

3. **TELEMETRY + PROOF** (change together — they are one contract):
   - Memory.stats gains construction/structure progress (e.g. extension
     built count or progress).
   - tests/integration.nix asserts the extension actually GETS BUILT,
     not merely that energy flows.

## Constraints (CLAUDE.md in full force)

- No policy, no state machines, no magic numbers in the shell. Ever.
- Never weaken a check to pass it — fix the spec or the shell.
- `paradox check --path dox` and the typecheck build are always fine;
  ask before `nix flake check` / `.#itest` (boots a VM).
- Agents: spec-author (dox), shell-hands (shell), tutorial-porter
  (section semantics), server-doctor (if the world goes quiet).

## Files

`dox/creeps.dox`, `shell/main.ts`, `shell/memory.d.ts`,
`tests/integration.nix`, `generated/` + `vendor/` via `nix run .#generate`
only.
```
