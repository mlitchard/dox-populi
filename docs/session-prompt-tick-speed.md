# Session prompt: parameterize Screeps server tick speed

## Problem

Tick duration is handled ad hoc in two places, inconsistently:

1. **`tests/integration.nix:264`** — hardcodes
   `system.setTickDuration(100)`, pushed best-effort over netcat to the
   server CLI (port 21026). The value 100 is a magic number buried in
   the test.
2. **`nix run .#server`** — always runs at the engine default (1000ms
   ticks). Dev iteration (deploy-local, watching a harvest, RCL
   grinding) crawls at 1s/tick with no way to speed it up short of
   hand-typing into `nix run .#cli`.

There is no single knob. The evolution-tournament plan
(docs/evolution-plan.md) needs fast generations, and itest wall-clock
time is dominated by tick rate — both want this parameterized once,
not sprinkled.

## Plan

One knob, defined in the flake, working out of the box. NOBODY has to
set an environment variable to get the right behavior — the default
lives as a `let` binding in `flake.nix` (e.g. `tickMs = 100;`), and
`SCREEPS_TICK_MS` is an OPTIONAL per-shell override, same pattern as
`SCREEPS_HOST` / `SCREEPS_IDENTITY`.

### Changes

1. **`flake.nix` let block**: `tickMs` binding — the single source of
   truth, consumed by both the server app and the itest wiring.
2. **`flake.nix` server app**: push
   `system.setTickDuration(''${SCREEPS_TICK_MS:-<tickMs>})` to the CLI
   after the launcher is up — same nc-to-21026 pattern the itest
   already uses. Best-effort with a visible echo of what was (or
   wasn't) set. Needs a readiness wait: the launcher is backgrounded,
   so the CLI port may not be bound yet when the push fires.
3. **`tests/integration.nix`**: take a `tickMs ? 100` argument
   (package-normal-form, same as `testName`) and use it in the
   `setTickDuration` helper — kill the inline magic number. `flake.nix`
   passes the same `tickMs` binding explicitly at the wiring site.
4. Keep the itest's best-effort semantics: deadlines already cover the
   un-compressed 1s worst case, and a failed CLI push must never fail
   the test. Preserve that contract.

### Open questions (settle in-session, before writing code)

- Does `setTickDuration` persist in `.server-data` storage across
  server restarts? If yes, decide: re-assert every launch (knob is
  authoritative) vs. only set when the env var is present (world
  remembers). Pick one and document it in the app's echo output.
- Input validation: the value goes into a CLI expression — accept
  digits only, reject anything else loudly.

### Constraints

- nix-pipeline agent territory: `flake.nix` + `tests/integration.nix`
  only. No brain/hands changes — tick speed is server ops, not policy.
- Avoid any route that touches `server/npm/package.json` or
  `server/mods/package.json` (would force a re-lock); the CLI route
  needs no new dependencies.
- Cheap checks freely (`nix eval` the drvs); `.#itest` is expensive —
  the user runs it.

### Result

- `nix run .#server` — fast dev loop by default, zero setup
- `SCREEPS_TICK_MS=1000 nix run .#server` — optional per-shell override
- itest tick compression driven by the same named flake binding
- The evolution orchestrator gets its generation-speed knob for free

## Files

`flake.nix`, `tests/integration.nix`. Nothing else.
