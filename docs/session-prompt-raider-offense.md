# Session prompt: the raider offense case — escalating waves until blood lands

## Problem

The live-raider arc is green (branch 11-attack-defense): raiders marched,
tower engaged, threat cleared, defender spawned, colony intact — every
link independently witnessed. But one charge was left on the docket, by
explicit ruling: **the raider's offense is unproven.** No live evidence
has ever shown a raider landing a blow, and the itest currently swears
only to movement (`pollRaiderMarched`: `hostileMoves >= 1`;
`damageTaken` printed, NOT asserted).

The evidence that forced the ruling (itest run #5):

- Raiders inserted at spawn±(3,3), marched exactly 2 diagonal steps each,
  died adjacent to the spawn — tombstones at (22,26)/(20,24), spawn
  (21,25).
- Spawn hits FULL, `actionLog.attacked` null,
  `stats.combat.damageTaken: 0`. Zero damage dealt.
- `hostileMoves: 4` = 2 moves per raider, then **stillness**.
- `memory:raiders` = `{"raiders":{}}` — brain ran, dead names pruned.

Two suspects, externally indistinguishable so far:

- **(A) Struct fact misfire**: `findInRange(FIND_HOSTILE_STRUCTURES, 1)`
  empty at adjacency (while `FIND_HOSTILE_SPAWNS` demonstrably works —
  the march proves it). Event stays `noFoeNoStructSpawn` → stuck in
  `marching`, moveTo a spawn it's already touching: moves nothing,
  swings nothing, dies.
- **(B) Intent rejection**: `razing` fires, `creep.attack(spawn)` is
  called, the engine rejects or drops the intent (rc != 0, or rc 0
  discarded downstream).

The fight resolves in <1s of real time at 50ms ticks — external CLI
sampling can NEVER see it (proven twice). Internal instruments only.

## The test design (user ruling)

**Escalating waves.** The itest does not assume any fixed raider count
is enough — it escalates force until damage happens:

1. Insert **1 raider**. Let the wave resolve (all raiders of the wave
   downed — cumulative `hostilesDowned` reaches the expected running
   total). Check `stats.combat.damageTaken`.
2. Zero damage? Insert **2**. Resolve, check. Then 3, then n, then
   **n+1 — until damage lands.**
3. The moment `damageTaken >= 1` latches: offense PROVEN, proceed to
   the rest of the arc (engaged / cleared / defender / intact).
4. A wave **cap** bounds the ordeal (melee raiders need adjacent tiles;
   the spawn's adjacency ring has at most 8 slots minus terrain — cap
   ≤ 8 is the natural ceiling; decide in session, as a named test
   constant, not magic). Cap reached with zero damage = the probe
   FAILS and the attack path is convicted by exhaustion.

Why this design is sound: the tower processes ONE target per tick at
≤600 dmg. If the sword works at all, some n saturates that throughput —
survivors stand adjacent with tail-protected ATTACK parts and blood
MUST land. If NO n draws blood, no physics excuse remains: the bug is
proven, and the flight recorder (Act 1) names the statute.

## Plan

### Act 1 — instrument (hands-layer telemetry, no policy)

Add a flight recorder to shell/invader.ts, the exact `Memory.trace`
precedent from the colony shell:

- Per raider, record `{t, event, fsm, rc}` into the raiders user's
  memory — **append-on-change ONLY** (user ruling): a new entry is
  written only when `{event, fsm, rc}` differs from that raider's last
  recorded entry; a steady state is one line, not one per tick (the
  colony Memory.trace discipline exactly). It must LATCH PAST DEATH
  (do not prune a dead raider's trace with its FSM entry; the trace is
  the tombstone that talks).
- The loop currently DISCARDS `execute()`'s return
  (`ScreepsReturnCode | null`) — capture it. Ordering note: memory is
  written before execute today; the rc must be recorded AFTER execute.
- Extend the `Memory.raiders`/trace declaration in shell/memory.d.ts
  (tsc is the witness that shell and shape agree).
- tests/integration.nix `forensicsRaiders` already dumps
  `memory:raiders` — widen the `.slice(0, 400)` if the trace needs
  room. The itest inherits the new bundle through the flake seed step
  automatically; the dev world needs reseed or users.code surgery
  (user's call).

### Act 2 — the wave protocol in the itest

Rework the raid subtest in tests/integration.nix:

- Parameterize the insertion surgery by wave size and wave index
  (unique names, e.g. `raider-w<wave>-<i>`; spread insert positions so
  raiders don't fight for the same approach tile).
- Python wave loop: insert wave n → poll wave resolution (cumulative
  `hostilesDowned` == sum of all wave sizes so far) → check
  `damageTaken` → break on blood, escalate on zero, fail at cap with
  the recorder dumped in the diagnosis.
- Downstream probes adjust to cumulative arithmetic:
  `pollThreatCleared`'s `hostilesDowned >= 2` becomes the computed
  running total + `hostiles == 0`; defender spawn may fire during any
  wave (threat is threat); `pollColonyIntact` unchanged at the end.
- Print forensics between waves — each wave is also a recorder run,
  so even the PASSING trial documents which n drew first blood and
  what the losing waves' FSMs were doing.

### Act 3 — verdict and the stronger oath

- **Blood at some n ≤ cap**: offense proven. The probe asserts
  `damageTaken >= 1` (the movement-only oath is retired). Read the
  recorder anyway: if waves 1..n-1 show `marching` stuck at adjacency
  or nonzero rc, that's a real bug worth a fix even though brute force
  eventually landed — file it honestly, fix in the correct layer
  (spec if vocabulary, shell if projection).
- **Cap with zero damage**: the recorder discriminates —
  `fsm: marching` forever ⇒ (A) observation bug; `razing, rc != 0` ⇒
  (B) named by the code; `razing, rc: 0` with no damage ⇒ engine
  drops the processed intent — server-doctor digs into the vendored
  engine via UPSTREAM source (npm/GitHub), never /nix/store. Fix the
  real bug, rerun the ordeal. Never weaken a check to route around it.

### Opportunistic (only if elbow-deep already)

- tests/fsm-behavior.ts has NO oracle sweep for the invader machine —
  the colony machines got the exhaustive states×events treatment; the
  invader brain deserves the same church.
- `nix run .#gitlab-ci > .gitlab-ci.yml` regeneration if flake outputs
  changed.

## Diagnostics available

- Live CLI from host: VM forwards 21026;
  `(printf 'CMD\n'; sleep 3) | nc -N -w 6 127.0.0.1 21026`. ONE JS
  expression per line — no semicolons, no for-loops; errors are often
  SILENT (add `.catch(e => "ERR:" + ...)` + marker grep).
- `forensicsRaiders` (tests/integration.nix): raider positions/hits/
  actionLog.attack + spawn hits/attacked + `memory:raiders`.
- Full NPC-user case file (engine uid-2 curse, seeded-user recipe,
  server-managed `active` re-armed at insertion, CLI quirks): session
  memory topic `screeps-npc-user.md`. The wave surgery must keep the
  `active: 10000` re-arm in every wave's CLI session.
- Tick knob 50ms: each wave resolves in ~1s wall-clock; the wave loop's
  poll budgets stay small.

## Constraints

- Brain/hands law: the recorder is hands-layer TELEMETRY (Memory.stats
  church), not policy. Wave escalation is TEST protocol (world surgery
  + probes), not brain policy — the invader brain stays deterministic
  and dumb; the test varies force, not behavior.
- `Memory.stats`/trace shapes and tests/integration.nix probes change
  together.
- Never hand-edit generated/ or vendor/; never read /nix/store.
- Cheap checks freely (`paradox check --path dox`, typecheck,
  fsm-behavior). `.#itest` boots a VM — the user runs it (established
  pattern; it's fast). `reset-local` is the user's call.
- Probes must be able to FAIL — the cap is what keeps the ordeal
  honest.

## Result

- A per-tick record of what the raider brain saw, decided, and got
  back from the engine — durable past death, readable by existing
  forensics.
- An itest that finds the MINIMUM force that draws blood and asserts
  `damageTaken >= 1` at it — offense proven by escalation, or the
  attack path convicted by exhaustion with the recorder naming the
  root cause.
- The full arc, no link on faith: raiders moved AND drew blood, the
  defense answered, the threat cleared, the defender stood up, the
  colony healed.

## Files

`shell/invader.ts`, `shell/memory.d.ts`, `tests/integration.nix`;
`dox/invader/invader.dox` only if the verdict indicts the vocabulary;
`tests/fsm-behavior.ts` opportunistically; generated/ + vendor/ are
build outputs.
