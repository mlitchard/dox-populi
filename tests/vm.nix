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
    # vm/module.nix receives `self` via specialArgs in the real
    # nixosConfigurations.vm; provide it the module-args way here.
    _module.args.self = self;
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("seed service populates ~/dox-populi as a real git repo"):
        machine.wait_for_unit("dox-populi-seed.service")
        machine.succeed("test -d /home/dev/dox-populi/.git")
        machine.succeed("test -f /home/dev/dox-populi/flake.nix")
        machine.succeed("su - dev -c 'git -C ~/dox-populi rev-parse HEAD'")

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
