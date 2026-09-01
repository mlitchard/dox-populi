# Off-series: The Section 1 Baseline

Title: unruled.

Status: OFF-SERIES (ruled 2026-08-31). Unnumbered, linked between post
zero and post one. The numbered posts walk the stages a reader stands
on; this page patches the record. Branch: tutorial-one.

## What this post is

The project's session record starts at Screeps tutorial section 2. The
section 1 work — the first spec, the first harness, the first passing
checks — was done before transcript capture began, and an agent sweep of
docs/unedited confirmed the hole. This post tells that plainly and shows
the patch: a section 1 baseline derived from the repo's earliest commit,
deployed live, witnessed running. The reader learns the smallest
complete state of the apparatus and sees how a hole in a record gets
labeled instead of papered over.

## Objectives (stated first; every exercise maps to one)

1. How to read the smallest complete state of the apparatus: the spec
   (one union, one constant), the harness loop, the flake's three
   checks.
2. How to read what each check rejects: `paradox check` verifies the
   spec's named properties; `tsc` makes a mismatch between the harness
   and the generated decision logic a compile error; the build
   assembles `main.js`.
3. How to deliver code to the Screeps server and watch it run.

## Promise

- Open with the hole: the series shows every step of the build, and the
  record of the first step was never kept. This post is the honest
  repair.
- The derivation claim, stated up front: the baseline is the earliest
  commit with the section-2 forward declarations removed.
- The three objectives about the apparatus (1–3), phrased as skills.
- Side-by-side candidate: `section1/role.harvester.js` from the
  official tutorial against the tutorial-one harness loop — the same
  behavior, with the role's body coming from the spec.

## Session

Source: the 2026-08-31 session transcript (this derivation session).
PENDING: export into docs/unedited before drafting; every quote
verifies against the exported file. No quotes drafted until it lands.

Arc (dialogue format per the post-zero ruling, his prompts bold
verbatim):
1. "I'm in trouble claude" — the missing section 1, staged-session idea
   on the table.
2. Staged session rejected: one fake entry poisons the record.
3. The bind: a fresh redo starts from the finished architecture, and
   the original minimal step can't be recovered by pretending.
4. The derivation: the earliest commit is a period artifact; subtract
   the section-2 forward declarations (`upgrader`, `builder` in the
   CreepRole union); the one edit to dox/creeps.dox.
5. Delivery: `nix flake check`, `nix run .#deploy`, spawn placement,
   respawn closer to the source.
6. Arc ends at the achieved goal: "i see a creep moving."

## Proof

- Screenshot of the harvester in the room (taken 2026-08-31, scrot).
- GIF of the harvest-deliver cycle, matching the other posts' proof
  format. PENDING.

## Postscript (exercises grouped by objective)

Objective 1 — read the smallest state:
- Check out tutorial-one. Read dox/creeps.dox and harness/main.ts.
  Mark every Screeps API call; all of them sit in the harness. Find
  where the creep's body comes from; it comes from the spec.

Objective 2 — what each check rejects:
- Remove `harvester` from the CreepRole union and run
  `nix flake check`. Read what `paradox check` and `tsc` each say.
- Restore the spec. Change the harness to use a role the union does
  not declare, run the check again, and read the compile error.

Objective 3 — deliver and watch:
- Deploy to your own Screeps account (`nix run .#deploy` with your
  token) and watch the harvester spawn, harvest, and deliver.

Assignment (LAST exercise, per outline law): the session prompt that
starts the harvester/upgrader stage — the ground of post one
(1-tutorial-one). Exact prompt artifact chosen at draft time.

## Open items

- Transcript export to docs/unedited (his act; blocks Session quotes).
- Title ruling.
- ISO for the tutorial-one stage: build + Hetzner hosting, link in
  Promise/Postscript.
- GIF for Proof.
- This branch has no itest; checks are paradox-check, typecheck,
  build. The live run is the witness — the post says this plainly.
