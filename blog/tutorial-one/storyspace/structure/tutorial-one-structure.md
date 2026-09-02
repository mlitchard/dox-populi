# Storyspace: the tutorial-one subgraph

The shape and vocabulary come from blog-series-structure.md (ROOT →
INTERIOR → EXIT, edges labeled fast / meander / dig). This file is
tutorial-one's own map: the concrete nodes, the real files behind them,
and the paths a reader can take. Scope is this branch only.

Reader stands on: the `tutorial-one` branch and its stage ISO.
Throughline: accessibility.

## Nodes

ROOT — blog/tutorial-one/promise.md
  The record-repair promise: the section-1 port, and the missing
  original record. Its own story is the derived baseline (outline.md
  is its working outline; promise-outline.md is the beat guide). States
  the objectives as skills, names branch + ISO, offers the first path
  choice.

INTERIOR
  port — blog/tutorial-one/session.md
    How tutorial 1 was ported: the real 2026-08-31 session, the
    derivation from the earliest commit.
  arrival — storyspace/structure/arrival-outline.md
    The no-purchase requirement exhausts the field; cleanroom the
    prior art. Carries the joke and the LLM-summary edge.
  build — storyspace/structure/build-outline.md
    Server then viewer: the unattended build, the recorded agent
    failure, the player's acts restored. Ends at the witnessed loop.

LINK (not a node) — blog/tutorial-one/gui-bot-challenge.md
  A reader challenge reachable from the build node: implement
  GUI-driven placement, keep instances locally isolated, run multiple
  bots, then automate placement as an experiment. A link off to the
  side, not a step on any path.

EXIT — blog/tutorial-one/postscript.md
  Exercises mapped to objectives, then the assignment. Ends with the
  one forward pointer: check out tutorial-two.

  The forward branch does not exist yet. tutorial-two is created later,
  by the merge (tutorial-one + 2-tutorial-two → tutorial-two). While
  tutorial-one is being authored, its EXIT names a branch that is not
  there. The checkout is a real act only in the finished, merged-up
  series, where every stage branch exists. So the fast-path reader —
  ROOT straight to EXIT, skipping everything — is pointed at a branch
  that comes into being only once the whole thing has accumulated
  toward main.

## Paths

- fast:            ROOT → EXIT   (skips the port node)
- accessibility:   ROOT → arrival → build → EXIT
- full:            ROOT → port → arrival → build → EXIT

The gui-bot challenge is a link off the build node, not a path step.

## Exercise index (always on screen)

storyspace/structure/exercise-index.md — the persistent panel of every
exercise reached so far, for backtracking to skipped ones. Grows as the
reader moves through nodes; entries link to their node and objective.

## Edges (each states what it gives and what it costs)

From ROOT:
  → run it and move on                              → EXIT        (fast)
  → the port itself                                 → port        (meander)
  → why we had to build the viewer                  → arrival     (meander)

From port:
  → on to the accessibility build                   → arrival     (meander)
  → skip ahead and run it                           → EXIT        (fast)

From arrival:
  → build the server and viewer                     → build       (meander)

From build:
  → try it yourself: GUI placement + automation     → gui-bot     (dig, link)
  → down to the protocol contract                   → docs/viewer-contract.md (dig)
  → down to the viewer code                         → viewer/src/ (dig)
  → on to the exercises                             → EXIT        (meander)

## Open

(none)
