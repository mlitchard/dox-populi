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
