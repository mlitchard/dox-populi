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
    virtualisation.memorySize = 16384;
    virtualisation.sharedDirectories.repodir = {
      source = "${self}";
      target = "/home/dev/dox-populi";
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("host repo is live-mounted at ~/dox-populi over 9p"):
        # The mount is nofail: multi-user.target does not wait for it.
        machine.wait_for_unit("home-dev-dox\\x2dpopuli.mount")
        machine.succeed("mountpoint -q /home/dev/dox-populi")
        machine.succeed("test -f /home/dev/dox-populi/flake.nix")

    with subtest("sshd is up for host editor integration"):
        machine.wait_for_unit("sshd.service")
        machine.wait_for_open_port(22)

    with subtest("determinate nix drives the guest"):
        machine.succeed("nix --version | grep -q 'Determinate Nix'")
        machine.wait_until_succeeds("determinate-nixd status")

    with subtest("flakes are enabled for the dev workflow"):
        machine.succeed(
            "grep -E 'experimental-features.*flakes' /etc/nix/nix.custom.conf"
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
