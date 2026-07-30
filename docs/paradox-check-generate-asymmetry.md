# Paradox finding: `check` / `generate` machine-verification asymmetry

Found 2026-07-30 while porting tutorial section 3 (branch `3-tutorial-3`):
a spec that `paradox check` accepted was rejected by `paradox generate`.
Upstream bug in Paradox, recorded here until it's filed/fixed.

## Symptom

A spec using one shared state union across multiple machines (each
machine's `states:` dict covering only its own subset of the union)
passes `paradox check --path dox` cleanly, then fails
`nix run .#generate` with:

```
[error]: Reachability        — Unreachable states: <all foreign states>
[error]: Deadlock freedom    — Deadlocked states (no outgoing transitions): ...
[error]: Complete coverage   — Missing transitions: (<foreign state>, <event>) ...
```

Machine verification treats the machine's state space as the WHOLE
union, so every variant not in that machine's `states:` dict is
unreachable/deadlocked/uncovered — but only `generate` runs that
verification at all.

## Mechanism (it's an omission, not a disagreement)

In `lib/src/Paradox/Commands.hs`:

- **`generate`** (line 815, verification at 830–834): strap →
  `runCheckHooks` → `extractMachines` + `verifyMachine` per machine,
  `throwError` on any report. This is where the Reachability /
  Deadlock freedom / Complete coverage obligations
  (`lib/src/Paradox/State/Verify.hs`) are enforced.
- **`check`** (line 935–943): strap → `runCheckHooks` → done. No
  `extractMachines`, no `verifyMachine`; the check command does not
  import `Paradox.State.Verify` at all.

So `paradox check` applies no FSM verification whatsoever — machine
properties are enforced only at generate time.

## Provenance

- Introduced: `d88d277c` (2026-02-22, "Merge paradox-state into lib as
  first-class state machine support") — the only commit touching
  `verifyMachine` wiring; it was wired into `generate` only.
- Present through HEAD `4231e71ad6ececb7a85d68d52b5b34ba6704eacf`
  (2026-06-02), which is also the rev pinned by this repo's
  `flake.lock`.

## Suggested upstream fix

Hoist the `extractMachines`/`verifyMachine` block into the shared strap
path (or duplicate it in `check`) so both commands enforce identical
obligations. One-liner for the report:

> `check` (Commands.hs:935) omits the `extractMachines`/`verifyMachine`
> block that `generate` (Commands.hs:830–834) runs inside strap;
> introduced in d88d277c, present through 4231e71a. Fix: hoist machine
> verification into the shared strap path so both commands enforce the
> same obligations.

## Consequence for dox-populi

`dox/creeps.dox` uses per-role state unions (`HarvesterState`,
`UpgraderState`, `BuilderState`) as machine state types, plus an
all-names `CreepState` namespace union for `StateBehaviors` /
`RoleSpec.initial` — instead of one shared-union design. If upstream
ever verifies machines over only their declared states, the shared
union becomes viable again (one transition-function signature, no
per-machine ownership guards in the shell).

Moral: this is why the pipeline runs generate-then-typecheck instead of
trusting `check` alone — two gates, one truth.
