# Session prompt: detsys binding — branch 13, one MR for binds #2/#3/#4

## Context (what's already true — do not re-derive)

- v0.1.0 is LIVE on FlakeHub (`mlitchard/dox-populi`, unlisted). Publish
  path: `.github/workflows/flakehub.yml` fires on SemVer tags pushed to
  the github.com/mlitchard/dox-populi mirror (3rd origin push-URL).
  GitHub is the identity notary ONLY — no tests run there. Tag-after-
  green-GitLab is the trust bridge. This is working as intended (FlakeHub
  trusted-issuer model), NOT a workaround — frame it that way everywhere.
- Our self-hosted GitLab's OIDC issuer is permanently untrusted by
  api.flakehub.com (401 at /token/status, receipts on file). The DetSys
  GitLab component was yanked from the flake's gitlab overlay; comment at
  the yank site records why.
- FlakeHub Cache facts (from docs.determinate.systems, verified): push =
  trusted builders only (GitHub Actions/Semaphore/Buildkite — NOT GitLab,
  not even gitlab.com); pull = JWT via `determinate-nixd login`; paid
  plans only. Therefore bind #5 (cache) is DEAD for this project and
  `include-output-paths: false` stays. Anonymous qemu users can never
  pull FlakeHub Cache — the qemu-only on-ramp is untouchable and FIRST
  in every doc.
- Paradox is PUBLIC: gitlab.com/paradox_labs/paradox. Its author fully
  supports this project.
- Goal behind the goal: bind dox-populi tighter to detsys (Determinate
  Systems) — user is courting a detsys job. Field-report tone, receipts
  over flattery. Every bind must earn its keep technically; no
  cargo-culting, no decoration.

## Mission: branch `13-detsys-binding`, one MR

### Phase 0 — receipts first (no repo mutations)
Every claim below arrives with its receipt (lock entry, fetch, search
result) or it doesn't arrive:
1. Fetch DeterminateSystems/determinate (FlakeHub/GitHub): confirm exact
   `nixosModules.<attr>`, its option surface, and known conflicts with
   custom `nix.settings`.
2. Inventory which flake inputs exist on FlakeHub (candidates: disko;
   check the rest of the lock). typed-screeps is non-flake — stays
   GitHub. secrix / gitlab-ci are Platonic repos — verify, don't assume.
3. Confirm `fh` package attr exists in our pinned nixpkgs.
4. Paradox-on-FlakeHub ask: draft one message to the paradox author
   proposing he publish to FlakeHub (his call, no timeline pressure —
   gitlab input keeps working meanwhile). If published:
   `flakehub.com/f/paradox_labs/paradox/*` becomes the centerpiece input.

### Phase A — bind #3: FlakeHub SemVer inputs
5. Migrate Phase-0-confirmed inputs to `https://flakehub.com/f/...`
   URLs (SemVer range chosen per project, `*` only where sane).
6. `nix flake lock`; inspect diff — same revs expected, new resolution
   URLs. Any rev CHANGE gets examined before proceeding.

### Phase B — bind #2: Determinate Nix in VM + ISO (flagship)
7. Add input `determinate.url =
   "https://flakehub.com/f/DeterminateSystems/determinate/*"`.
8. Import the confirmed module in `vm/module.nix` (shared module — vm,
   installer, installed system inherit from one import point).
9. Read vm/module.nix's nix config against the module's options BEFORE
   building (determinate-nixd has opinions). dd-installer + 9p mount
   should be inert — verified by the check, not asserted.

### Phase C — bind #4: fh in devShell + README
10. Add `pkgs.fh` to the devShell.
11. README: "living on FlakeHub" section — fh/FlakeHub consumption for
    already-converted nix users. Qemu-only on-ramp stays FIRST and
    unchanged. Optional: FlakeHub badge.

### Phase D — compliance gauntlet
12. `nix run .#gitlab-ci > .gitlab-ci.yml` (regenerate; diff should be
    empty — prove it).
13. Cheap checks: `packages.default`, typecheck.
14. `checks.vm-boot` = the decisive witness for #2 — ASK USER before
    running (VM-boot tier). installer-iso rebuild = expensive, user's
    call; CI builds nixosConfigurations anyway.

### Phase E — ship
15. Commit (user asks), MR into main, GitLab green.
16. Tag v0.2.0 → FlakeHub release whose contents ARE the detsys binding.
    Consider flipping workflow visibility to "public" at this release —
    user's call.
17. blog/roadmap.md: add posts "The best nix install is the one nobody
    runs" (#2) and "Living on FlakeHub" (#3/#4); reframe post 12 blurb
    to "working as intended".

## Parallel track — #6 (external repos, NOT this MR)
- PR-1 to gitlab.com/DeterminateSystems/flakehub-push (local clone:
  ~/gitlab/flakehub-push): component.yml hardcodes
  NIX_INSTALLER_NETRC/NIX_INSTALLER_EXTRA_CONF to
  /home/gitlab-runner/cache, ignoring the `tmpdir` input — two-line fix,
  production-tested in our repo before the yank. Can ship today.
- PR-2: fail-fast when CI_SERVER_HOST != gitlab.com (component) and/or
  decode+print JWT `iss` on 401 (Rust binary, github repo).
- PR-3: docs asterisk — "GitLab CI supported" means gitlab.com only.
- Feature request (server-side, words only): scoped issuer registration
  — org registers instance URL, OIDC discovery + JWKS, domain-validated,
  trust scoped to (issuer, namespace) per registered org. File AFTER
  PR-1 lands, citing it. Companion ask: GitLab OAuth login.

## Working style (session contract)
- User executes many commands himself — propose, then expect takeover.
- No unrequested verification chains after his actions.
- NEVER model from vibes: fetch docs/source before behavioral claims.
- Voice per CLAUDE.md.
