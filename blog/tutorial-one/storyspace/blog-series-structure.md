# Storyspace: the series as a hypertext

The series is not a line of posts. It is a graph the reader traverses,
and every path ends at the finished project on `main`. A reader picks
how direct the route is: the fast path is a few nodes and the
exercises; the meander path visits every side node — the failures, the
corrections, the fights. Same destination, different works, per reader.

## Scope is local to the branch

The whole graph is never authored in one place. Each `tutorial-N`
branch builds out only its own stage's subgraph — the work here on
`tutorial-one` deals only with tutorial-one.

The graph accumulates by git merge, one stage at a time. Two families
of branches:

- `N-tutorial-N` (2-tutorial-two, 3-tutorial-three, …): the code
  stage — the tutorial's spec/harness/flake work.
- `tutorial-N`: the accumulating branch — all prior stages' blog and
  code, plus stage N's blog built on top.

When tutorial-one's blog is done, its next stage is born by merging
the running blog branch and the next code branch into a new one:

  tutorial-one  +  2-tutorial-two  ──merge──▶  tutorial-two
  tutorial-two  +  3-tutorial-three ──merge──▶ tutorial-three
  …
  tutorial-(last) ──merge──▶ main

So each `tutorial-N` carries everything before it; the storyspace grows
with every merge instead of being written whole. The last merge lands
the finished project — and the finished hypertext — in main.

A branch knows exactly two things about the spine: its own subgraph,
and the single forward pointer its EXIT carries — the name of the next
stage the reader checks out. It does not author or depend on that next
stage's contents; that stage is built after the merge that creates it.

The forward pointer names a branch that does not exist yet. While a
stage is being authored, its EXIT names the next stage's branch, which
the later merge has not created. The checkout is a real act only in the
finished, merged-up series, where every stage branch exists. A reader
who takes the fast path — straight from ROOT to EXIT, skipping every
interior node — is pointed at exactly such a not-yet-created branch.

Each forward arrow is also a real act for the reader: check out the
next branch and boot its ISO. No node advances the reader except the
EXIT node, which names the checkout out loud.

## A tutorial is a subgraph, not a page

Each tutorial stage is its own hypertext with a fixed shape. The shape
is what carries forward between branches — not content, just the
pattern — so when a later branch is built out, it builds the same
shape for its own stage:

- ROOT node — the stage's promise. States objectives as skills, names
  the branch and ISO the reader stands on, and offers the first
  choice of path. Every reader enters here.
- INTERIOR nodes — one story each (a port, a repair, a build, a
  failure). Optional to any given path. Objectives-first, so a reader
  arriving mid-path knows at once whether the node serves them.
- EXIT node — the assignment. Ends by naming the next branch to check
  out (the subgraph's one forward pointer). Every path leaves here.

Rule the shape enforces: ROOT and EXIT are on every path; INTERIOR
nodes are what the path length varies over. A node never silently
drops the reader into the next stage — only EXIT does that, and it
does it out loud.

- TRENCHES slot — every stage carries one. Hand-work on code the
  agent wrote for this stage: the student reshapes real lines by hand,
  then runs the stage's checks and witnesses that behavior held. The
  craft beat of the throughline — the code becomes yours by working
  it — so it sits on every path, in its own file linked from the
  stage's exercises.

## Edges carry intent

A bare link makes a maze; a labeled link makes a path. Every edge
states what taking it gives the reader and roughly what it costs:

  → run it and move on            (fast)
  → how this was actually fought  (meander)
  → the layer beneath (code/docs) (dig)

The fast path is the subset of edges labeled fast; it always exists
and always reaches EXIT.

## The exercise index is always on screen

A persistent panel holds links to every exercise the reader has
reached so far, so a skipped exercise stays reachable. It accumulates
along the path and, through the merges, across stages — each merged
stage's exercises join it. For now expressed as a file per stage
(tutorial-one: storyspace/structure/exercise-index.md). An exercise
enters the panel once its node is reached; each entry links to its
node and names the objective it serves.

## Discipline that keeps the graph a set of tutorials

- Every node keeps answering which stage it serves. The graph is
  tutorials-with-texture, never a homepage of essays.
- Every node stands on the same branch+ISO as its stage's ROOT, so a
  reader's feet are on one stage no matter where the path wanders.
- The lesson-plan law holds per node: objectives up front, every
  exercise mapped to one.

## Each stage's concrete map lives with the stage

This file holds the series shape only. A stage's concrete map — its
real files, nodes, paths, and edges — lives in that stage's own
storyspace. tutorial-one's map is
storyspace/structure/tutorial-one-structure.md.

## The next stage

When tutorial-one's blog is done, merge `tutorial-one` and
`2-tutorial-two` into a new `tutorial-two` branch. The blog work then
resumes there: blog/tutorial-two/ gets its own ROOT, interior nodes,
and EXIT (whose forward pointer names tutorial-three, or main if it is
the last stage). tutorial-one's storyspace rides along in the merge,
so the graph on tutorial-two already contains this stage. Each merge
adds a stage; the last merge into main holds the whole.

## Open

- The throughline label for the accumulated graph: accessibility.
