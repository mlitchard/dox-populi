# NixOS dev VM for people WITHOUT nix on their host. Built by
# `nix build .#vm-image` (qcow2, see run-vm.sh for the qemu wrapper).
#
# The guest is the real dev environment: nix + flakes, the repo seeded
# at ~/dox-populi, the store pre-warmed with the devshell and app
# closures. The Steam-bundled Screeps server is proprietary and is NOT
# shipped — users run fetch-screeps-server (their own Steam account,
# they must own the game) to install it where apps.server expects it.
{ pkgs, lib, self, ... }:
let
  fetchScreepsServer = pkgs.writeShellApplication {
    name = "fetch-screeps-server";
    runtimeInputs = [ pkgs.steamcmd ];
    text = ''
      # Downloads Screeps (appid 464350) with YOUR Steam account — you
      # must own the game. Installs to the path `nix run .#server`
      # expects by default.
      read -rp "Steam username: " STEAM_USER
      exec steamcmd \
        +@sSteamCmdForcePlatformType linux \
        +force_install_dir "$HOME/.local/share/Steam/steamapps/common/Screeps" \
        +login "$STEAM_USER" \
        +app_update 464350 validate \
        +quit
    '';
  };
in
{
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

  # Room for in-VM builds; the image is sparse so this costs little.
  virtualisation.diskSize = 40 * 1024;

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

  # Pre-warm the nix store: referencing the devshell and app programs
  # here roots their closures (paradox, z3, node toolchain, steam-run,
  # curl/jq plumbing) in the image, so first use inside the VM needs no
  # rebuilds — only flake-input source downloads at eval time.
  environment.etc."dox-populi/prewarmed-closures".text =
    lib.concatStringsSep "\n" [
      "${self.devShells.x86_64-linux.default}"
      "${self.packages.x86_64-linux.main}"
      self.apps.x86_64-linux.server.program
      self.apps.x86_64-linux.deploy-local.program
      self.apps.x86_64-linux.cli.program
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
        git commit -qm "seed from vm-image"
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
                                       flake inputs; everything else is
                                       pre-warmed)
      4. nix run .#server            — private server on host port 21025
      5. nix run .#deploy-local      — push main.js, place Spawn1

    Play: point the Steam client ON THE HOST at localhost:21025
    (Private server — ports 21025/21026 are forwarded by run-vm.sh).

    ~/work is your host directory (if shared via run-vm.sh).
    SSH from the host: ssh -p 2222 dev@localhost  (password: dox-populi)
  '';
}
