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

  fileSystems."/home/dev/vm-keys" = {
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
  environment.variables.WORKDIR = "/home/dev/vm-keys";
  environment.variables.SCREEPS_IDENTITY = "/home/dev/vm-keys/identity";

  environment.loginShellInit = ''
    if [ -d ~/dox-populi ]; then cd ~/dox-populi; fi
  '';

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
      nix run .#server         — start the game server
      nix run .#deploy-local   — deploy the bot
      nix run .#client         — start the viewer, then open
                                 http://localhost:8080 in the HOST browser

    Credentials set up? docs/SECRIX.md has the walkthrough.
  '';
}
