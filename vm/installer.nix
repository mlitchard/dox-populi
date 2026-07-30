# Auto-installing ISO for the dev VM (the dubai installer-auto-dd
# pattern): a systemd service on the installer does the whole install
# on boot — no human interaction. run-vm.sh boots this ISO with an
# empty disk; the service partitions /dev/vda, runs nixos-install for
# nixosConfigurations.vm from the repo source embedded in the ISO (the
# guest's nix builds everything — nothing is built on the host), and
# powers off. Progress streams to the serial console.
#
# Built once by someone with nix: `nix build .#installer-iso`.
{ pkgs, lib, self, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  # run-vm.sh is serial-only (-nographic/tmux): put boot and install
  # output on the serial console.
  boot.kernelParams = [ "console=ttyS0,115200" ];

  # installation-cd enables ZFS support, which pulls in this option's
  # deprecated default (true). Nothing here roots on ZFS; false is the
  # 26.11 default and avoids force-importing a possibly-live pool.
  boot.zfs.forceImportRoot = false;

  # The ISO file is named "<image.baseName>.iso" (isoImage.isoName is a
  # dead alias since 25.05); mkForce beats installation-cd-base's value.
  image.baseName = lib.mkForce "dox-populi-installer";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  systemd.services.dox-populi-auto-install = {
    description = "auto-install the dox-populi dev VM to /dev/vda";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.parted
      pkgs.e2fsprogs
      pkgs.util-linux
      pkgs.systemd
      pkgs.nixos-install-tools
      pkgs.nix
      # nix shells out to `git` to fetch plain git+https flake inputs
      # (e.g. paradox's nix-parsec) while evaluating this flake.
      pkgs.git
    ];
    serviceConfig = {
      Type = "oneshot";
      # Show progress on the (serial) console, not just the journal.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -euo pipefail
      # Refuse to touch a disk that is already partitioned.
      if [ -e /dev/vda1 ]; then
        echo "dox-populi: /dev/vda already partitioned — skipping auto-install"
        exit 0
      fi
      echo "=== dox-populi auto-install: partitioning /dev/vda ==="
      parted -s /dev/vda -- mklabel msdos mkpart primary ext4 1MiB 100%
      udevadm settle
      mkfs.ext4 -F -L nixos /dev/vda1
      # Explicit -t ext4: right after mkfs, blkid/udev can lag and
      # mount's fs autodetection fails (tries FAT, ISOFS, gives up).
      udevadm settle
      mount -t ext4 /dev/vda1 /mnt
      echo "=== nixos-install: building the system inside the VM (takes a while) ==="
      nixos-install --no-root-passwd --flake ${self}#vm
      echo "=== pre-building dev shell, server, and client into the installed system ==="
      # Build from the installer side into the target store — the same
      # pattern nixos-install itself uses to populate /mnt. (nixos-enter
      # would chroot into /mnt, where a fresh install has no resolv.conf,
      # so substituters would be unreachable.)
      # NOTE: no `nix flake archive` here — it force-fetches ALL flake
      # inputs, including gitlab-ci's git+ssh URL, which the installer
      # can never reach (no ssh, no key). First `nix develop` in the VM
      # re-downloads eval sources (nixpkgs, paradox) but builds nothing.
      nix build --store /mnt --no-link \
        ${self}#devShells.x86_64-linux.default \
        ${self}#screeps-server \
        ${self}#screeps-client
      echo "=== install complete — powering off; rerun ./run-vm.sh to boot ==="
      poweroff
    '';
  };
}
