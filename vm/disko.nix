# Separate from vm/module.nix so tests/vm.nix can boot module.nix in the
# NixOS test harness without pulling in disko or image machinery.
#
# GPT on /dev/vda: 1M EF02 BIOS-boot (vda1), ext4 root (vda2). Installer
# dd's the image, then sgdisk -e + growpart + resize2fs to fill the real
# disk. type="gpt" required — type="table" breaks eval.
{ ... }:
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/vda";
    imageSize = "16G";
    content = {
      type = "gpt";
      partitions = {
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
            extraArgs = [ "-L" "nixos" ];
            mountpoint = "/";
          };
        };
      };
    };
  };
}
