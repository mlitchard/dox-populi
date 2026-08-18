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
      3. nix run .#server            — private server on host port 21025
                                       (nix-vendored — no Steam needed)
      4. nix run .#deploy-local      — provision account, push main.js,
                                       place Spawn1
      5. nix run .#client            — (optional) browser client on host
                                       port 8080. Uses ~/work/package.nw,
                                       which run-vm.sh links there
                                       automatically from the host's
                                       Steam install of the game

    Secrets (secrix, same workflow as native nix):
      Apps decrypt secrets with YOUR key. Place it in the host dir
      run-vm.sh shares (~/vm-keys by default; WORKDIR= to override)
      named "identity" — it appears here as ~/work/identity, which
      SCREEPS_IDENTITY already points to.
      (Or export SCREEPS_IDENTITY=/path/to/your/key yourself.)
      deploy-local reads secrets/SCREEPS_LOCAL_CREDS ("username:password"),
      or set SCREEPS_LOCAL_EMAIL / SCREEPS_LOCAL_PASSWORD instead.
      Encrypt your own secrets to it (from the dev shell), e.g.:
        secrix create secrets/SCREEPS_LOCAL_CREDS -i "$SCREEPS_IDENTITY" -r "$(cat $SCREEPS_IDENTITY.pub)"

    Play: point the Steam client ON THE HOST at localhost:21025
    (Private server — ports 21025/21026 are forwarded by run-vm.sh).

    ~/work is your host directory (if shared via run-vm.sh).
    SSH from the host: ssh -p 2222 dev@localhost  (password: dox-populi)
  '';
}
