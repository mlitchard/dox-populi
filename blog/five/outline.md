# Blog post five — outline

**Title:** First Blood
**Branch:** `11-attack-defense`
**Source transcripts:** `docs/unedited/2026-08-01-this-session-*.txt`,
`docs/unedited/2026-08-02-this-session-*.txt`
**Source artifacts:** `docs/session-prompt-raider-offense.md`,
`docs/session-prompt-live-invader.md`

## 1. The Promise

- The setup: the colony gets an enemy. The raider's decision logic comes
  off the same pipeline as everything else — a Paradox spec, checked,
  generated, typechecked — seeded into the server as an NPC user. Then
  the war has to be tested, and testing it takes two sessions of the
  author cross-examining his own tests and his own laws.
- What you'll learn:
  1. The enemy gets no special treatment — the raider's decision logic
     is Paradox-specified, same pipeline, and lives on the server as an
     NPC user (the uid-2 engine quirk and the raiders-user workaround).
  2. A test may claim only what the world produced — and how you force
     the world to produce more: the escalating-wave protocol, n raiders
     then n+1 until damage happens.
  3. Rulings are code too — the author's own two laws deadlock the
     tower at 990 energy, and the no-surgery doctrine gets amended by
     its own author: one arming write, then observation only.
- Jargon links out on first use: NPC, cron.

## 2. The Session

Two sessions, told in order. Candidate receipts (line numbers into
each transcript; verify every quote at draft time). Author's questions
in bold. Curation law: no quoting ghosts — the ERR_NO_BODYPART
masquerade is cited from the code comment, because no dialogue exists
for it.

### Session one — 2026-08-01: the honest oath

- **~260** — "why is damageTaken off the stand?" — the author
  cross-examining his own weakened test. The answer on record: run #5
  produced zero damage, and a probe that demands a fact the world
  doesn't deliver "isn't a check, it's a hunger strike."
- **~309** — "ship as is, strengthening test is it's own task." — the
  test reduced to what the world produced (hostileMoves >= 1); the
  offense question filed as its own task instead of buried.
- **~725–727** — the escalating-wave protocol, in the author's own
  words: "you create 1 raider, raider dies without giving damage. then
  2 are made, not enough? okay three then n then n + 1 until damage
  happens." If no n draws blood, the attack path is convicted by
  exhaustion.
- NPC-user law as context: uid-2 creeps run the engine's own invader
  AI and never load seeded code, so the raiders exist as a dedicated
  NPC user plus a uid-2 stub. Cited from the commit record.

### Session two — 2026-08-02: the laws collide

- ~20–28 — the two-laws deadlock: the tower-refill latch closes at
  1000 and reopens below 500; the raid gate demands a full 1000
  tower. The tower fires one shot — ten energy — 990. Below the
  gate's bar, above the reopen line, forever. On record: "Your two
  rulings deadlock the moment the tower spends a dime. The creeps
  ain't broken — they're obeying."
- **~41** — "what problem are you trying to solve right now" →
  **~75** — "what does this mean 'rewriting the spec so a tower is a
  sink whenever it's below 1000'" → **~109** — "do it". The author
  amending his own law under evidence.
- ~413–427, ~492–496 — the surgery doctrine, the second
  self-amendment: the total no-surgery ruling gives way to exactly ONE
  arming write (RCL 3, safe mode off, raid goal crossed, tower
  standing); everything after is observation and tick pacing.
- The fail→fix→pass on the arming write: **~1124** — "you did not set
  up correct conditions, the gates are still locked" → **~1495** —
  "do you understand why this is a problem, the gates should startt
  open, they are clearly not open" with the poll output quoted →
  arming write rebuilt to insert the tower directly (~1249–1255) →
  first blood asserted: cumulative damageTaken >= 1.
- ERR_NO_BODYPART masquerade, one paragraph, cited from the code
  comment: the engine returns ERR_NO_BODYPART (-12) for every hostile
  action while safe mode runs — the code reads like a missing body
  part and actually means the world forbids hostile actions; the raid
  mod reads that signal and defers raids until safe mode lapses.

Curation notes: the deadlock is the doctrinal peak of the series —
every prior post shows the human as the final word; this one shows the
final word revising itself under evidence. Spend excerpt budget on
"why is damageTaken off the stand?" and the deadlock verdict. The
escalating-wave quote runs whole; it's the author designing the
evidence.

## 3. The Proof

- GIF: raiders against the tower, first blood on camera.
- Still: the itest SUCCESS poll line — war conditions seeded, damage
  latched.
- Optional re-shoot, decided at draft time: check out the pre-fix
  commit and capture the deadlock itself — the tower stalled at 990
  while creeps walk past it.
- Caption law: every capture names the command that produced it.

## 4. The Postscript

- Exercises:
  1. (objective 1) Read the raider machine in `dox/invader/`. Then
     grep `shell/` for raider decision logic — find where the raider's
     choices actually live. Find the raiders user and the uid-2 stub
     in the seed step.
  2. (objective 2) Read the first-blood probe in
     `tests/integration.nix`. State exactly what `damageTaken >= 1`
     shows. State what it leaves open.
  3. (objective 3) Reconstruct the deadlock from the two laws: latch
     closes at 1000, reopens below 500; raid gate demands 1000. Walk
     the tower from full to 990 and explain why no creep ever feeds it
     again. Then read the sink-below-1000 law that replaced it.
  4. (objective 2) Read `docs/session-prompt-raider-offense.md` and
     `docs/session-prompt-live-invader.md` — the author's written
     orders for both sessions. Check each success criterion against
     the evidence in this post — find where the post shows it, or
     fails to.
- Stretch (objective 3): ask an LLM how a set of individually
  reasonable rules can jointly deadlock, then verify its answer
  against the two laws in this post. The interrogation habit, sixth
  rep.
