{ pkgs, lib, modulesPath, vmImageZst, ... }:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];

  boot.kernelParams = [ "console=ttyS0,115200" ];

  # installation-cd enables ZFS support, which pulls in this option's
  # deprecated default (true). false avoids force-importing a possibly-live pool.
  boot.zfs.forceImportRoot = false;

  # isoImage.isoName is a dead alias since 25.05; image.baseName is the live option.
  image.baseName = lib.mkForce "dox-populi-installer";

  # Plain file in the ISO filesystem keeps the payload image out of the
  # installer's closure. iso-image.nix mounts the ISO at /iso at runtime.
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
      pkgs.util-linux # blockdev, findmnt, lsblk, partprobe, sfdisk (growpart backend)
      pkgs.cloud-utils # growpart
      pkgs.gptfdisk # sgdisk
      pkgs.e2fsprogs # e2fsck, resize2fs
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
    script = ''
      set -euo pipefail
      IMAGE=/iso/install/image.raw.zst
      TARGET=/dev/vda

      # Idempotence: a partitioned disk means an already-installed system.
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
      # growing anything.
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
