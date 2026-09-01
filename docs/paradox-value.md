# What Paradox is for, and what it brings this project

Findings from a read of the Paradox repo (~/gitlab/paradox: README, the
Antora docs, the checker and codegen source, FINDINGS.md), 2026-09-01.

## What the tool is

Paradox is a domain specification language with a multi-target
compiler. Its own positioning: "A language for domain specification"
(README) that "compiles to multiple target languages. You define your
types, validation rules, and display logic once in `.dox` files, and
Paradox generates correct, idiomatic code" for seventeen targets
(docs index). The static checking exists in service of the compiling:
it rejects a spec that is internally contradictory before any code is
generated from it.

## The value for dox-populi

The spec (`dox/creeps.dox`) is where decisions live because Paradox is
the compiler that turns it into the decision logic the harness
imports. One source, one authority; the harness consumes generated
types and functions instead of hand-copied ones, so the spec and the
running code cannot drift apart by hand-editing. The check in front of
generation means a contradictory spec is rejected before it becomes
code.

One generation policy the repo defends explicitly and tests
cross-target: every backend runs declared validators at runtime — "No
backend silently degrades validation to a no-op"
(docs/codegen/overview.adoc), pinned by a cross-target test suite.

## What `paradox check` covers

In order: import resolution, type presence, kind consistency,
SMT-based type checking of every declaration (constraint solving via
Z3), refinement satisfiability, exhaustiveness and pattern checks,
lemma checking. The rejection surface is enumerable — the error type
lists on the order of sixty-five distinct classes, each with a golden
test. The docs carry an accurate Limitations section
(advanced/smt-refinements.adoc): the solver does not inline function
bodies, complex arithmetic can time out, runtime values are out of
reach.

## Bounds that calibrate our claims

- Without Z3 on the path, refinement and division checks are silently
  skipped (fail-open, no CLI warning). Closed in this project: the
  flake's paradox-check derivation pins `z3` into its build inputs, so
  this pipeline never runs the degraded check.
- State-machine verification (determinism, reachability, deadlock
  freedom, coverage, liveness) runs under `generate`, never under
  `check`. Irrelevant to tutorial-one (no machines); relevant from
  section 2 on. Determinism checking skips guarded transitions;
  liveness is skipped for machines without final states.
- The F* story is layered: generation emits real lemma obligations for
  F*; `paradox check --fstar` runs F* in lax mode, which skips
  discharging them; the Paradox repo's own atlas CI runs full F*.
  "Generates proof obligations" is solid ground; where they get
  discharged depends on which runner.
- Inconclusive lemmas are warnings; `assume` marks a lemma as an
  unverified axiom and both check and codegen accept it.
- The repo's FINDINGS.md is blunt about known unsoundness in the
  checker's inference ("internal inference frequently collapses
  'unknown' ... into the real language type `Unit` ... Unsoundness.").
  An alpha tool being honest with itself, which fits how this blog
  treats green checks as smaller than they look.

## The sentence for the blog

Paradox rejects an inconsistent spec and generates the decision logic
the harness imports.
