# NixOS dev VM for people WITHOUT nix on their host. Nothing is built
# on the host: run-vm.sh boots the official NixOS installer ISO in
# qemu, and vm/install.sh (run inside the live installer) installs this
# configuration (flake output nixosConfigurations.vm) onto the virtual
# disk — the guest's own nix does all the building.
#
# The guest is the real dev environment: nix + flakes, the repo seeded
# at ~/dox-populi; everything (devshell, apps, the nix-vendored Screeps
# server) is downloaded and built inside the VM. Nothing proprietary is
# shipped or fetched — watching the game happens on the HOST (Steam
# client or browser client bridge, both need the user's own game copy).
{ pkgs, self, modulesPath, ... }:
{
  # Virtio drivers in the initrd (disk, net, 9p).
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  system.stateVersion = "25.05";
  networking.hostName = "dox-populi";
  networking.firewall.enable = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "dev" ];
  };

  # run-vm.sh launches qemu -nographic: serial console is the terminal.
  boot.kernelParams = [ "console=ttyS0" ];

  # Grub in the MBR of the virtual disk (partitioned by vm/install.sh).
  boot.loader.grub.device = "/dev/vda";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  users.users.dev = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "dox-populi";
  };
  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "dev";

  # For editor integration from the host (VSCode/Cursor Remote-SSH via
  # localhost:2222).
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;

  # Host directory shared by run-vm.sh (9p tag "workdir"); absent share
  # is fine (nofail).
  fileSystems."/home/dev/work" = {
    device = "workdir";
    fsType = "9p";
    options = [ "trans=virtio" "version=9p2000.L" "msize=524288" "rw" "nofail" ];
  };

  # Bind the Screeps server on all guest interfaces: qemu's hostfwd
  # delivers to the guest NIC, which loopback-bound services never see.
  environment.variables.SCREEPS_HOST = "0.0.0.0";
  # Guest mount point of the host directory shared by run-vm.sh
  # (WORKDIR= on the host; 9p tag "workdir").
  environment.variables.WORKDIR = "/home/dev/work";
  # Convention: users place THEIR OWN secrix identity key in the shared
  # dir as "identity" (no particular key is shipped or assumed). Apps
  # fail with instructions if the file is absent when a secret needs
  # decrypting; override per-shell by re-exporting SCREEPS_IDENTITY.
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

  # Seed the repo on first boot. The flake source has no .git, but the
  # apps anchor themselves with `git rev-parse --show-toplevel`, so make
  # it a real repository.
  systemd.services.dox-populi-seed = {
    description = "seed ~/dox-populi from the baked flake source";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "dev";
      RemainAfterExit = true;
    };
    path = [ pkgs.git ];
    script = ''
      if [ ! -e /home/dev/dox-populi/.git ]; then
        mkdir -p /home/dev/dox-populi
        cp -r --no-preserve=mode ${self}/. /home/dev/dox-populi/
        cd /home/dev/dox-populi
        git init -q
        git config user.name dev
        git config user.email dev@dox-populi.local
        git add -A
        git commit -qm "seed from installed flake source"
      fi
    '';
  };

  users.motd = ''

    dox-populi dev VM
    =================
    Quickstart:
      1. cd ~/dox-populi
      2. nix develop                 — the dev shell (first run downloads
                                       and builds everything in the VM)
      3. nix run .#server            — private server on host port 21025
                                       (nix-vendored — no Steam needed)
      4. nix run .#deploy-local      — provision account, push main.js,
                                       place Spawn1

    Secrets (secrix, same workflow as native nix):
      Apps decrypt secrets with YOUR key. Place it in the host dir you
      share via run-vm.sh (WORKDIR=...) named "identity" — it appears
      here as ~/work/identity, which SCREEPS_IDENTITY already points to.
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
