# The NixOS dev VM. Nothing is built at install time: this
# configuration is baked into a raw disk image (packages.vm-image,
# disk layout in vm/disko.nix), and the installer ISO
# (vm/installer.nix) just dd's that image onto the virtual disk —
# provisioned one-time via `nix run .#installer-iso`, then run with
# ./run-vm.sh.
{ pkgs, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  system.stateVersion = "25.05";
  networking.hostName = "dox-populi";
  networking.firewall.enable = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dev" ];
  };

  boot.kernelParams = [ "console=ttyS0" ];

  users.users.dev = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "dox-populi";
  };

  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "dev";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;

  fileSystems."/home/dev/work" = {
    device = "workdir";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "msize=524288" "rw" "nofail" ];
  };

  fileSystems."/home/dev/dox-populi" = {
    device = "repodir";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "msize=524288" "rw" "nofail" ];
  };

  environment.variables.SCREEPS_HOST = "0.0.0.0";
  environment.variables.WORKDIR = "/home/dev/work";
  environment.variables.SCREEPS_IDENTITY = "/home/dev/work/identity";

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
    pkgs.curl
    pkgs.jq
  ];

  users.motd = ''

    dox-populi dev VM
    =================
    Quickstart:
      1. cd ~/dox-populi
      2. nix develop                 — the dev shell (pre-baked into
                                       the VM image — ready immediately)
      3. nix flake check             — Paradox checks the spec, tsc
                                       typechecks the harness, the
                                       build bundles main.js
      4. nix run .#server            — private server on host port 21025
                                       (nix-vendored — no purchase needed)
      5. nix run .#deploy-local      — provision account, push main.js,
                                       place Spawn1
      6. nix run .#client            — browser viewer on host port 8080
                                       (open-source renderer, offline)

    Watch: open http://localhost:8080 in the HOST browser and sign in
    with your deploy-local credentials.

    Credentials: deploy-local reads SCREEPS_LOCAL_EMAIL /
      SCREEPS_LOCAL_PASSWORD, or age-encrypted
      secrets/SCREEPS_LOCAL_CREDS ("username:password"). Your key goes
      in the host dir run-vm.sh shares (~/vm-keys by default; WORKDIR=
      to override) named "identity" — it appears here as
      ~/work/identity, which SCREEPS_IDENTITY already points to.
      Encrypt your own creds to it (from the dev shell):
        secrix create secrets/SCREEPS_LOCAL_CREDS -i "$SCREEPS_IDENTITY" -r "$(cat $SCREEPS_IDENTITY.pub)"

    ~/work is your host directory (if shared via run-vm.sh).
    SSH from the host: ssh -p 2222 dev@localhost  (password: dox-populi)
  '';
}
