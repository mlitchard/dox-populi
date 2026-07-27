# NixOS dev VM for people WITHOUT nix on their host. Nothing is built
# on the host: run-vm.sh boots the official NixOS installer ISO in
# qemu, and vm/install.sh (run inside the live installer) installs this
# configuration (flake output nixosConfigurations.vm) onto the virtual
# disk — the guest's own nix does all the building.
#
# The guest is the real dev environment: nix + flakes, the repo seeded
# at ~/dox-populi; everything (devshell, apps) is downloaded and built
# inside the VM. The Steam-bundled Screeps server is proprietary and is NOT
# shipped — users run fetch-screeps-server (their own Steam account,
# they must own the game) to install it where apps.server expects it.
{ pkgs, lib, self, modulesPath, ... }:
let
  fetchScreepsServer = pkgs.writeShellApplication {
    name = "fetch-screeps-server";
    runtimeInputs = [ pkgs.steamcmd ];
    text = ''
      # Downloads Screeps (appid 464350) with YOUR Steam account — you
      # must own the game. Installs to ~/screeps: force_install_dir is
      # silently IGNORED for paths inside steamcmd's own Steam root
      # (~/.local/share/Steam), so it must live outside it. The system
      # sets STEAM_SCREEPS_DIR so `nix run .#server` finds it.
      read -rp "Steam username: " STEAM_USER
      exec steamcmd \
        +@sSteamCmdForcePlatformType linux \
        +force_install_dir "$HOME/screeps" \
        +login "$STEAM_USER" \
        +app_update 464350 validate \
        +quit
    '';
  };
in
{
  # Virtio drivers in the initrd (disk, net, 9p).
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  system.stateVersion = "25.05";
  networking.hostName = "dox-populi";
  networking.firewall.enable = false;

  # steam-run / steamcmd (unfree) — same predicate as the flake.
  nixpkgs.config.allowUnfreePredicate =
    pkg: lib.hasPrefix "steam" (lib.getName pkg);

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

  # Where fetch-screeps-server installs the game; apps.server honors it
  # (must point at the `server` subdir — it runs $STEAM_SCREEPS_DIR/resources/node).
  environment.variables.STEAM_SCREEPS_DIR = "/home/dev/screeps/server";
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
    fetchScreepsServer
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
      1. fetch-screeps-server        — install the Screeps server (your Steam
                                       account; you must own the game)
      2. cd ~/dox-populi
      3. nix develop                 — the dev shell (first run downloads
                                       and builds everything in the VM)
      4. nix run .#server            — private server on host port 21025
      5. nix run .#deploy-local      — push main.js, place Spawn1

    Secrets (REQUIRED — secrix, same workflow as native nix):
      Apps decrypt secrets with YOUR key. Place it in the host dir you
      share via run-vm.sh (WORKDIR=...) named "identity" — it appears
      here as ~/work/identity, which SCREEPS_IDENTITY already points to.
      (Or export SCREEPS_IDENTITY=/path/to/your/key yourself.)
      Encrypt your own secrets to it (from the dev shell), e.g.:
        secrix create secrets/STEAM_TOKEN -i "$SCREEPS_IDENTITY" -r "$(cat $SCREEPS_IDENTITY.pub)"

    Play: point the Steam client ON THE HOST at localhost:21025
    (Private server — ports 21025/21026 are forwarded by run-vm.sh).

    ~/work is your host directory (if shared via run-vm.sh).
    SSH from the host: ssh -p 2222 dev@localhost  (password: dox-populi)
  '';
}
