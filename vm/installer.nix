# Auto-installing ISO for the dev VM (the dubai installer-auto-dd
# pattern, dd edition): the ISO carries a PREBUILT zstd-compressed
# disk image of nixosConfigurations.vm (packages.vm-image-zst) and a
# boot service that decompresses it straight onto /dev/vda, grows the
# root partition to fill the disk, and powers off. No nix, no git, no
# network at install time — the image was built by whoever built the
# ISO. Progress streams to the serial console.
#
# Provisioning entry point: `nix run .#installer-iso` (the flake app)
# creates the qcow2 and boots this ISO once; `nix build .#installer-iso`
# builds the bare ISO. run-vm.sh only runs the installed system.
#
# vmImageZst arrives via specialArgs from flake.nix (the package
# compressing the disko-built raw image).
{ pkgs, lib, modulesPath, vmImageZst, ... }:
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

  # Ship the compressed system image as a plain file in the ISO
  # filesystem — NOT a store path in the installer's closure (same
  # deliberate decoupling as dubai's --post-format-files). At runtime
  # the live system mounts the ISO at /iso (iso-image.nix declares
  # fileSystems."/iso"), so the service reads it from
  # /iso/install/image.raw.zst.
  isoImage.contents = [
    {
      source = "${vmImageZst}/image.raw.zst";
      target = "/install/image.raw.zst";
    }
  ];

  systemd.services.dox-populi-auto-install = {
    description = "dd the prebuilt dox-populi dev VM image onto /dev/vda";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.zstd
      pkgs.coreutils
      pkgs.util-linux # dd's friends: blockdev, findmnt, lsblk, partprobe, sfdisk (growpart backend)
      pkgs.cloud-utils # growpart
      pkgs.gptfdisk # sgdisk: relocate the GPT backup header after dd
      pkgs.e2fsprogs # e2fsck, resize2fs
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      # Show progress on the (serial) console, not just the journal.
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -euo pipefail
      IMAGE=/iso/install/image.raw.zst
      TARGET=/dev/vda

      # Idempotence: a partitioned disk means an installed system —
      # never clobber it (same contract as the old installer).
      if [ -e "''${TARGET}1" ]; then
        echo "dox-populi: $TARGET already partitioned — skipping auto-install"
        exit 0
      fi

      echo "=== dox-populi auto-install (dd): sanity checks ==="
      if [ ! -f "$IMAGE" ]; then
        echo "error: $IMAGE not found on the ISO" >&2
        exit 1
      fi
      if [ ! -b "$TARGET" ]; then
        echo "error: $TARGET is not a block device" >&2
        lsblk -nd -o NAME,SIZE,TYPE || true
        exit 1
      fi
      if findmnt --source "$TARGET" >/dev/null 2>&1; then
        echo "error: $TARGET is mounted — refusing to overwrite" >&2
        findmnt --source "$TARGET" || true
        exit 1
      fi

      echo "=== writing system image to $TARGET ==="
      echo "source: $IMAGE ($(stat --format=%s "$IMAGE" | numfmt --to=iec) compressed)"
      zstd -d -c "$IMAGE" | dd of="$TARGET" bs=4M status=progress conv=fsync

      echo ""
      echo "=== refreshing partition table ==="
      partprobe "$TARGET" || echo "warning: partprobe failed; continuing"
      udevadm settle --timeout=30 || true

      # The image is smaller than the disk, so after dd the GPT backup
      # header sits at the image's end, not the disk's — move it before
      # growing anything (dubai's sgdisk -e step).
      echo "=== relocating GPT backup header to end of disk ==="
      sgdisk -e "$TARGET"
      partprobe "$TARGET" || true
      udevadm settle --timeout=10 || true

      # Partition 1 is the BIOS-boot partition; root is partition 2
      # (see vm/disko.nix).
      echo "=== growing root partition to fill the disk ==="
      growpart "$TARGET" 2
      partprobe "$TARGET" || true
      udevadm settle --timeout=10 || true

      echo "=== resizing root filesystem ==="
      # e2fsck exit 1 = "errors corrected" — acceptable after a grow.
      e2fsck_exit=0
      e2fsck -fy "''${TARGET}2" || e2fsck_exit=$?
      if [ "$e2fsck_exit" -gt 1 ]; then
        echo "error: e2fsck failed with exit code $e2fsck_exit" >&2
        exit 1
      fi
      resize2fs "''${TARGET}2"
      sync

      echo "=== final layout ==="
      lsblk -f "$TARGET" || true

      echo "=== install complete — powering off; rerun ./run-vm.sh to boot ==="
      poweroff
    '';
  };
}
