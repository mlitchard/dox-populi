# Session prompt: arm the scarecrow — live hostiles + real defense policy

## Problem

The tutorial platform is DONE (sections 1–5 green), but the defense proof
is a stage play. Two convictions from the test-suite prosecution still
stand, and they are this session's docket:

1. **The itest invader is a scarecrow.** `surgeryInsertInvader`
   (tests/integration.nix ~303-323) inserts a creep owned by the seed's
   Invader NPC user (uid "2") — whose script is the EMPTY seed stub. The
   creep has an `attack` part it never uses; it stands at spawn+(3,3) and
   waits to die. Consequences:
   - "invader dies to the tower" proves the tower can delete a stationary
     object, not that it can defend.
   - `pollColonyIntact` proves nothing — the colony "survived" an attack
     that never happened. (Battle damage is currently faked separately by
     `surgeryDamageExtension` setting hits to 1.)
2. **Defense policy is minimal.** One tower, attack-over-repair, no threat
   gradations, no defender creeps, no rampart/wall story. The spec's
   defense vocabulary (`sawHostile > sawDamage > quiet`, tower FSM) was
   sized for the tutorial's dummy. The post-tutorial game — and the
   evolution tournament that inherits this vocabulary — needs defense
   observations and policy worth mutating.

One job: make the enemy real, then make the defense policy real, then make
the itest prove the second against the first.

## Plan

### Act 1 — arm the scarecrow (server-side hostile behavior)

Give the hostile an actual brain. Design decision to make IN SESSION after
tutorial-porter/server-doctor research — candidate mechanisms, in rough
order of preference:

- **Vendored invader bot AI**: the open-source server supports bot AIs
  (the stock seed's simplebots — MichaelBot et al. — are exactly this;
  CLI exposes `bots.*`). Vendor a small, DETERMINISTIC invader AI as an
  npm package under `server/mods/` (nix-vendored like screepsmod-auth):
  move toward the victim spawn, attack creeps/structures in reach.
  Deterministic beats clever — the itest needs reproducible aggression,
  not a good player. After touching `server/mods/package.json`, rerun
  `nix run .#lock-mods` (hard rule).
- **Reuse simplebot**: spawn a stock simplebot into/adjacent to
  lambdafan's room via CLI (`bots.spawn`-style surgery). Zero new
  vendoring, but its behavior is economy-first — verify it actually
  attacks before betting the subtest on it.
- **Rejected unless forced**: per-tick CLI puppeteering of the inserted
  creep (fragile, races the tick loop, policy hidden in test scripts).

Whatever the mechanism: hostile behavior lives server-side as WORLD
content, not in our shell, not in test poll scripts. The brain/hands split
governs our client; the enemy is part of the environment.

### Act 2 — defense policy worth the name (spec first, as always)

With a moving attacker, the defense vocabulary earns its keep. Spec-side
decisions (dox/creeps.dox, spec-author agent) — decide and DOCUMENT each:

- **Threat observations**: is one bit (`sawHostile`) enough, or does the
  brain need gradations — hostile count, proximity-to-spawn, tower energy
  reserve? Follow the tutorial-5 doctrine: orthogonal facts as a flat
  product union, shell projection stays mechanical, no priority masking.
- **Tower policy**: target selection under multiples (closest? lowest
  hits?), attack-vs-repair under threat, energy discipline (don't repair
  the tower dry while a hostile closes distance — the threshold-sink
  semantics from tutorial 5 already give the lever: towerEnergyTarget).
- **Defender role (stretch, decide scope honestly)**: a creep with
  attack/tough parts as the first post-tutorial role. If cut, record why
  in the spec; if in, it rides the existing RoleSpec machinery (bodies
  tier list, desired count possibly threat-conditional — which would be
  the FIRST population policy that reads an observation; that's an
  architecture step, treat it as one).
- **Repair policy**: battle damage is no longer synthetic. Decide who
  heals what (tower repair vs. builder) and to what threshold.

Shell (shell-hands agent): new observations projected mechanically
(FIND_HOSTILE_CREEPS already exists; add whatever the vocabulary needs —
counts, tower energy), new actions only if the spec demands them
(creep.attack for a defender). Zero policy in the shell. Ever.

### Act 3 — the itest stops lying (execute the scarecrow sentence)

- Replace the scarecrow subtest: insert/spawn the LIVE hostile, then prove
  with `Memory.trace` + stats (durable evidence, not one-tick transients —
  the tutorial-5 lesson) that:
  1. the hostile MOVED and DEALT damage — creep or structure hits dropped,
     or a combat death occurred (telemetry may need a combat block:
     e.g. `stats.combat = {damageTaken, towerKills, deathsByCombat}` —
     `Memory.stats` is the telemetry contract, change stats and probes
     together);
  2. the defense ENGAGED (tower fired / defender fought — trace entries);
  3. the threat CLEARED (hostiles == 0, latched after engagement);
  4. the colony RECOVERED — `pollColonyIntact` finally testifying to a
     real fight: roleCounts restored, battle damage repaired, economy
     heartbeat (controllerProgress) unbroken.
- `surgeryDamageExtension` becomes redundant if the live invader deals
  real structure damage — remove it if so (superfluous tests are a
  convicted category; don't keep the fake wound next to the real one).
- Opportunistic, only if already elbow-deep in integration.nix: the
  `pollHarvesterSupporting` transient-window charge is still open —
  convert it to a `Memory.trace` probe.

## Diagnostics available (built for this — use them)

- Live CLI from host: VM forwards 21026;
  `(printf 'CMD\n'; sleep 3) | nc -N -w 6 127.0.0.1 21026`.
  Memory: `storage.env.get('memory:<uid>').then(m=>JSON.parse(m).stats)`
  (Promise). lambdafan uid 0f828899c06bb8a.
- `Memory.trace` flight recorder: per-machine (tick, event, fsm, action,
  rc) ring buffer, change-only. Tower entries carry hostile*/calm*.
- Stock seed simplebots (MichaelBot W9N9 borders lambdafan W9N8) reborn
  on every reset-local — free live-hostile material AND a confounder.
- Tick knob: `tickMs = 50` default; combat plays out ~20× wall-clock
  faster than stock — size poll budgets accordingly.
- VM console pane is server stdout — never send shell commands into it.

## Constraints

- Brain/hands split is law. Threat vocabulary, tower/defender policy,
  thresholds, repair doctrine → dox/creeps.dox. API calls + mechanical
  observation projection → shell/main.ts. Enemy AI → server world content
  (server/mods/), NOT our brain, NOT test scripts.
- `server/mods/package.json` changes require `nix run .#lock-mods` —
  nothing else runs npm's resolver.
- `Memory.stats` + tests/integration.nix probes change together.
- Never hand-edit generated/ or vendor/; never weaken a checker. Probes
  must be able to FAIL — the scarecrow conviction was exactly a probe
  that couldn't.
- Cheap checks freely (`paradox check --path dox`, typecheck,
  fsm-behavior). `.#itest` boots a VM — ask. `reset-local` wipes the dev
  world — user's call, and the new bot AI likely needs a reseed to take
  effect: raise this explicitly.
- Agents: tutorial-porter/server-doctor research the bot mechanism;
  spec-author owns Act 2; shell-hands wires; nix-pipeline vendors.

## Result

- A hostile that actually hostiles: deterministic, vendored, reproducible.
- Defense vocabulary and policy in the spec worth evolving — the first
  post-tutorial expansion of the brain, on the platform built for it.
- An itest where `pollColonyIntact` finally means what it says: the
  colony was attacked, defended itself, healed, and kept working — proven
  from the flight recorder, not asserted by a scarecrow.

## Files

`dox/creeps.dox`, `shell/main.ts`, `shell/memory.d.ts`,
`tests/integration.nix`, `server/mods/` (+ lock via `.#lock-mods`),
generated/ + vendor/ (build outputs). Flake only if vendoring/telemetry
wiring demands it.
