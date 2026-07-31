# Boots the dev VM system (vm/module.nix) in the NixOS test harness —
# same pattern as dubai/nix-workstation-image: package-normal-form
# `{ testers, nixosModule, ... }` instantiated via callPackage, with the
# module under test injected. Asserts the first-boot contract that
# run-vm.sh users depend on. Runs in plain `nix flake check`.
{
  testers,
  nixosModule,
  self,
  testName ? "dox-populi-vm-boot",
}:
testers.runNixOSTest {
  name = testName;

  globalTimeout = 10 * 60;

  nodes.machine = {
    imports = [ nixosModule ];
    virtualisation.memorySize = 2048;
    # Mirror run-vm.sh's repodir share via the test driver's native
    # shared-directory mechanism (mount tag = attr name, so "repodir"
    # matches the module's fstab entry): backs the module's
    # /home/dev/dox-populi 9p mount with the flake source.
    virtualisation.sharedDirectories.repodir = {
      source = "${self}";
      target = "/home/dev/dox-populi";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("host repo is live-mounted at ~/dox-populi over 9p"):
        # The mount is nofail, so multi-user.target does NOT wait for
        # it: checking mountpoint right away races the mount unit —
        # fast KVM hosts win, slow CI runners lose. Wait for the unit.
        machine.wait_for_unit("home-dev-dox\\x2dpopuli.mount")
        machine.succeed("mountpoint -q /home/dev/dox-populi")
        machine.succeed("test -f /home/dev/dox-populi/flake.nix")

    with subtest("sshd is up for host editor integration"):
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(22)

    with subtest("flakes are enabled for the dev workflow"):
        machine.succeed(
            "grep -E 'experimental-features.*flakes' /etc/nix/nix.conf"
        )

    with subtest("dev login environment is wired for the private server"):
        machine.succeed(
            "su - dev -c 'printenv SCREEPS_HOST' | grep -qx 0.0.0.0"
        )
        machine.succeed(
            "su - dev -c 'printenv SCREEPS_IDENTITY' | grep -qx /home/dev/work/identity"
        )

    machine.shutdown()
  '';
}
