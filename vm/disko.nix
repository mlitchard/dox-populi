# Disk layout for the dev VM (nixosConfigurations.vm), consumed both
# by the disko image builder (packages.vm-image bakes this layout into
# a raw image) and — via disko's generated config — as the installed
# system's fileSystems."/" definition.
#
# Deliberately a SEPARATE module from vm/module.nix: tests/vm.nix
# boots module.nix alone in the NixOS test harness (which supplies its
# own virtual root fs), so the test node never drags in disko or its
# image machinery.
#
# Contract: GPT on /dev/vda with a 1M BIOS-boot partition (EF02) for
# GRUB (still BIOS-booted via boot.loader.grub.device = "/dev/vda" in
# vm/module.nix — grub embeds core.img in the EF02 partition) and an
# ext4 root (partition 2) filling the rest. The installer dd's the
# image onto the 40G virtual disk, relocates the GPT backup header
# (sgdisk -e) and grows partition 2 to fill it.
#
# GPT, not msdos: disko's legacy "table" type is deprecated and breaks
# evaluation ("_config is read-only, but it's set multiple times" —
# the exact failure its deprecation warning documents). Migration per
# disko's docs/table-to-gpt.md.
{ ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    # Raw image size for the disko image builder: system closure plus
    # the pre-baked devshell/server/client (order of ~8G total) plus
    # comfortable headroom. Small enough to keep dd fast; the
    # installer grows the root partition to the real disk size.
    imageSize = "16G";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition: where grub-install puts core.img on a
        # GPT disk without EFI. Explicit priorities pin the partition
        # numbers: boot = vda1, root = vda2 (the installer's growpart
        # and resize2fs address partition 2).
        boot = {
          priority = 1;
          size = "1M";
          type = "EF02";
        };
        root = {
          priority = 2;
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            # Keep the "nixos" fs label for continuity/debugging.
            extraArgs = [ "-L" "nixos" ];
            mountpoint = "/";
          };
        };
      };
    };
  };
}
