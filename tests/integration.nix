# Integration test : boot a VM, start the
# private Screeps server (nix-vendored npm package), provision an
# account + push main.js + place Spawn1 (the production deploy-local
# script, unchanged), then poll the memory endpoint until (1) the spawn
# acquires energy (harvester works) and (2) the controller gains progress
# (upgrader works). Fully pure — runs in plain `nix flake check`.
{
  testers,
  writeShellScript,
  curl,
  jq,
  gzip,
  coreutils,
  # self.apps.*.program — the exact scripts users run
  serverProgram,
  deployProgram,
}:
let
  email = "itest";
  password = "itest-password";
  url = "http://127.0.0.1:21025";

  # One-shot probe: sign in, read Memory.stats.spawnEnergy (the loop's
  # telemetry) via GET /api/user/memory, which returns
  # {data: "gz:<base64 gzip of JSON>"}. Succeeds as soon as the spawn's
  # energy has risen since a previous observation — the spawn is
  # acquiring energy. Timing out (wait_until_succeeds) is the failure.
  pollSpawnEnergy = writeShellScript "poll-spawn-energy" ''
    set -euo pipefail
    STATE=/tmp/itest-spawn-energy
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.spawnEnergy" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.spawnEnergy in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    E=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "spawn energy: $E"
    if [ -f "$STATE" ] && [ "$E" -gt "$(cat "$STATE")" ]; then
      echo "spawn acquired energy"
      exit 0
    fi
    printf '%s\n' "$E" > "$STATE"
    exit 1
  '';

  # One-shot probe: sign in, read Memory.stats.controllerProgress via the
  # memory API. Succeeds as soon as progress > 0, proving the upgrader
  # collected energy and called upgradeController at least once.
  pollControllerProgress = writeShellScript "poll-controller-progress" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.controllerProgress" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.controllerProgress in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    P=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "controller progress: $P"
    [ "$P" -gt 0 ]
  '';
in
testers.runNixOSTest {
  name = "dox-populi-itest";

  nodes.machine = {
    # Server spawns storage/backend/engine children plus runner/processor
    # workers; the world db is an in-memory LokiJS.
    virtualisation = {
      memorySize = 4096;
      cores = 4;
    };

    systemd.services.screeps = {
      description = "dox-populi private Screeps server (headless)";
      wantedBy = [ "multi-user.target" ];
      environment = {
        SCREEPS_DATA_DIR = "/var/lib/screeps";
        # Any non-empty key disables Steam-native auth in the backend; the
        # account is provisioned over HTTP by deploy-local, so the key is
        # never actually used.
        STEAM_API_KEY = "itest-dummy";
      };
      serviceConfig = {
        ExecStart = serverProgram;
        Restart = "no";
      };
    };
  };

  testScript = ''
    import time

    machine.start()
    machine.wait_for_unit("screeps.service")
    print(">>> screeps.service is active")

    with subtest("server serves the HTTP API"):
        machine.wait_until_succeeds(
            "${curl}/bin/curl -fsS ${url}/api/version", timeout=300
        )
        version = machine.succeed("${curl}/bin/curl -fsS ${url}/api/version")
        print(f">>> server is up: {version.strip()}")
        print(">>> server log so far:")
        print(machine.succeed("journalctl -u screeps --no-pager | tail -n 25"))

    with subtest("deploy-local provisions account, pushes code, places spawn"):
        status, out = machine.execute(
            "SCREEPS_LOCAL_EMAIL=${email} "
            "SCREEPS_LOCAL_PASSWORD=${password} "
            "SCREEPS_DATA_DIR=/var/lib/screeps "
            "${deployProgram} 2>&1"
        )
        print(out.strip())
        if status != 0:
            raise Exception("deploy-local failed")
        print(">>> deploy-local finished: account provisioned, code pushed, Spawn1 placed")

    with subtest("spawn acquires energy"):
        # Explicit poll loop so every observation is visible in the log.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollSpawnEnergy} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: spawn acquired energy")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the spawn to acquire energy")
            time.sleep(2)

    with subtest("controller progress increases"):
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollControllerProgress} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: controller is being upgraded")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for controller progress")
            time.sleep(2)
  '';
}
