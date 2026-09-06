# CI job filter, read by the gitlab-ci.nix generator (`flake.gitlab
# or null`, applied to the generated config). The generator maps
# every flake output to a job; one job building the deepest
# artifact proves the whole chain. Dropped:
# - VM chain: apps:installer-iso embeds vm-image-zst <- vm-image
#   <- the vm system, so those upstream jobs are redundant.
# - checks:build and packages:main are the same derivation as
#   packages:default.
# - flake:check rebuilds every check the test stage already ran.
# - flake:show: gitlab-ci:check runs `nix flake show --json` itself.
# - apps:server / apps:deploy-local are baked into checks:itest
#   (serverProgram/deployProgram).
# removeAttrs, not `= null` (nulls survive into the YAML), plus a
# needs scrub (GitLab rejects undefined needs).
prev:
let
  dropped = [
    "nixosConfigurations:vm"
    "nixosConfigurations:installer"
    "packages:vm-image"
    "packages:vm-image-zst"
    "packages:installer-iso"
    "checks:build"
    "packages:main"
    "flake:check"
    "flake:show"
    "apps:server"
    "apps:deploy-local"
  ];
  scrubNeeds = _: job:
    if builtins.isAttrs job && job ? needs
    then job // {
      needs = builtins.filter (n: !(builtins.elem n dropped)) job.needs;
    }
    else job;
  filtered = builtins.mapAttrs scrubNeeds (builtins.removeAttrs prev dropped);
# FlakeHub publishing lives in GitHub Actions
# (.github/workflows/flakehub.yml): FlakeHub trusts github.com's
# OIDC issuer, not this GitLab instance's.
in filtered
