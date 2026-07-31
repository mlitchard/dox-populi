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
    # Mirror run-vm.sh's repodir share: export the flake source over 9p
    # so the module's /home/dev/dox-populi mount has a backend, exactly
    # like the host repo does in the real dev VM.
    virtualisation.qemu.options = [
      "-virtfs local,path=${self},mount_tag=repodir,security_model=mapped-xattr"
    ];
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("host repo is live-mounted at ~/dox-populi over 9p"):
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
