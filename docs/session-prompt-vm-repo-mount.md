# Session prompt: VM repo mount — real repo, not a snapshot

## Problem

The `dox-populi-seed` service in `vm/module.nix` copies `${self}` (a
nix store snapshot with no `.git`, no history, no branches) into
`~/dox-populi` and fakes a single-commit repo with `git init`. This is
useless for development — no history, no remote, no branch tracking.

## Agreed plan

Share the host repo directory into the VM via 9p read-write. The guest
works directly on the host's real repo. No copy, no clone, no seed.

### Changes

1. **`run-vm.sh`**: add a read-write 9p virtfs sharing `$REPO` (the
   script's own directory, already computed on line 48) with mount tag
   `repodir`. Same pattern as the existing WORKDIR share.

2. **`vm/module.nix`**: add a `fileSystems` entry mounting `repodir`
   at `/home/dev/dox-populi` (9p, read-write, `nofail`). Remove the
   `dox-populi-seed` systemd service entirely — there is nothing to
   seed when the repo is live-mounted from the host.

3. **`vm/installer.nix`**: no change. `${self}` in
   `nixos-install --flake ${self}#vm` stays — it builds the NixOS
   system from the baked source during install. The live mount only
   matters at runtime, not install time.

### Result

- Guest sees the host's working tree in real time (edits, branch
  switches, commits — all shared)
- Full git history, correct branch, real remote
- Host sees guest edits immediately (e.g. `nix run .#server` inside
  the VM modifies `.server-data/` visible on the host)

## Files

`run-vm.sh`, `vm/module.nix`. Do not touch `vm/installer.nix`.
