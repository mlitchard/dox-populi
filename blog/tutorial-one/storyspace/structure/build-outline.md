# Node: building the server and the viewer

Title: It doesn't work until it metts spec.

Note: This refers to the motivation of the latest task due to
the requirement of accessibility. The project's reach shrinks significantly
if I require screeps purchase or even Steam account.

Status: storyspace node attached to tutorial one. Throughline:
accessibility — the whole game loop (run, deploy, watch, interact)
from the ISO, nothing purchased, nothing on the host but QEMU and a
browser. Continues from the arrival node; the fast path enters
directly at "what you run."

Session source: the 2026-09-02 export (move to docs/unedited before
quotes are drafted). Supporting artifacts already in the repo:
docs/viewer-contract.md, the server-log excerpts.

## Objectives (skills, stated first)

1. How to vendor a hostile npm package with nix: the open server's
   isolated-vm git dependency, lockfile pinning, npmDepsHash, the
   lock-* apps that make npm's resolver run exactly once.
2. How to read a contract from published artifacts before writing
   code: the renderer's init sequence and state format from its repo
   and demo; the socket protocol from the reference clients; the
   metadata bundle that exports nothing and assigns a window global —
   facts fetched, never deduced.
3. How to kill a failure class by design: the same-origin proxy —
   serve the page and forward /api and /socket, and CORS stops
   existing as a concept, for every reader.
4. How to debug from the record: the backend crash loop read out of
   the server log (empty Steam key → greenworks hunt), the dummy-key
   fact, the status bar that turned silent failures into named ones.

## Arc (curated, trimming only; his corrections stay in)

0. The working rhythm, stated up front because it shapes everything
   after: the initial build ran unattended — the agent wrote the
   server port and the viewer for something like twenty minutes while
   he watched Better Call Saul. His involvement was light touch until
   the agent claimed the work ready for assessment. From that claim
   on, his engagement went dense: every correction beat below sits in
   the assessment phase. The effort lands where the trust doctrine
   puts it — the human inspects and decides; the typing was delegated.
1. Server port: vendored open server, auth mod, self-provisioning
   deploy. First run in the VM: crash loop in the log; the fix is one
   non-empty string.
2. Contract research before viewer code; the modules (connection,
   feed, render, inspect) and what each consumes.
3. The debugging chain, told honestly, as recorded agent failure:
   faced with the export-shape bug, the agent burned round after round
   trying to DEDUCE the interop shape — reasoning from how bundles
   usually export — when the answer was to read the published bundle.
   Only after wasting that time, and after he ruled "rely on
   documentation instead of deduction," did it fetch the bundle and
   find the metadata assigns a window global and exports nothing. The
   right first move was made last. This edge is the point: not a
   utopia pitch — the agent typed fast and reasoned badly, and the
   human's correction is what turned it toward the evidence.
4. The player's acts restored, on his correction ("stop making
   choices for me"): deploy stops at code push; respawn behind a
   confirm; click a tile to place Spawn1; the room shown is one where
   the click succeeds.
5. Arc ends at the witnessed loop: map, spawn placed by hand,
   harvester working, click shows its live fields.

## What you run (fast-path entry)

nix run .#server / .#deploy-local / .#client; host browser at
localhost:8080; credentials from secrets/SCREEPS_LOCAL_CREDS.

## Proof

- Server-log excerpts: the greenworks crash loop, then "Game server
  listening" and "tick duration set".
- Screenshot/GIF of the viewer: room, harvester, inspection panel
  (pending).
- docs/viewer-contract.md as the standing artifact of objective 2.

## Edges

- In: from the arrival node (meander) or straight from the
  tutorial-one page (fast).
- Down: docs/viewer-contract.md for the protocol layer;
  viewer/src for the code.
- Out: back to the tutorial-one page's exercises.

## Open

- Title; transcript move + quote verification; whether server and
  viewer split into two nodes; exercises (candidates: break the proxy
  path and read the named failure; place a spawn in a controller-less
  room and read the refusal); Proof captures.
