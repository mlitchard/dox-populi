# Integration test : boot a VM, start the
# private Screeps server (nix-vendored npm package), provision an
# account + push main.js + place Spawn1 (the production deploy-local
# script, unchanged), then poll the memory endpoint until (1) the spawn
# acquires energy (harvester works), (2) the controller gains progress
# (upgrader works), and (3) an extension is built (builder + spec-driven
# extension placement work). Fully pure — runs in plain `nix flake check`.
{ testers
, writeShellScript
, curl
, jq
, gzip
, coreutils
, netcat-openbsd
, # self.apps.*.program — the exact scripts users run
  serverProgram
, deployProgram
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

  # One-shot probe: read Memory.stats.creeps, a per-creep record of
  # {role, event, fsm, action} written by the shell every tick. Succeeds
  # when a harvester's event is "sinksFull" while its fsm is "harvesting" —
  # proof that emitEvent correctly emits the compound "creep full AND every
  # energy sink (spawn + extensions) full" signal in the real game runtime,
  # and the FSM transitions to idle.
  pollHarvesterSinksFull = writeShellScript "poll-harvester-sinksfull" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.creeps" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.creeps in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    JSON=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "creep stats: $JSON"
    # Succeed if ANY harvester has event=sinksFull and fsm=harvesting.
    printf '%s' "$JSON" | ${jq}/bin/jq -e '
      to_entries | map(select(
        .value.role == "harvester"
        and .value.event == "sinksFull"
        and .value.fsm == "harvesting"
      )) | length > 0
    ' > /dev/null
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

  # One-shot probe: read Memory.stats.extensionsBuilt — the tutorial-3
  # end-to-end proof: RCL reached 2, the shell placed the spec-driven
  # extension construction site, and the builder hauled 3000 energy into
  # it. Succeeds when at least one extension structure exists. Also prints
  # stats.extensionProgress and stats.controllerLevel for diagnosis while
  # the build is still in flight.
  pollExtensionBuilt = writeShellScript "poll-extension-built" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    decode() {
      local path="$1" data
      data=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
        "${url}/api/user/memory?path=$path" | ${jq}/bin/jq -r '.data // empty')
      case "$data" in
        gz:*) printf '%s' "''${data#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat ;;
        *) printf 'absent' ;;
      esac
    }
    N=$(decode stats.extensionsBuilt)
    echo "extensions built: $N (progress: $(decode stats.extensionProgress), RCL: $(decode stats.controllerLevel))"
    [ "$N" != absent ] && [ "$N" -ge 1 ]
  '';

  # Tick compression: the extension needs RCL 2 (200 controller progress)
  # and then 3000 build-energy — far too slow at the default 1s tick. The
  # server CLI on 21026 accepts system.setTickDuration(ms); best-effort
  # (the test still passes at 1s ticks, just near the deadline).
  setTickDuration = writeShellScript "set-tick-duration" ''
    printf 'system.setTickDuration(100)\n' \
      | ${netcat-openbsd}/bin/nc -q 2 127.0.0.1 21026
  '';
in
testers.runNixOSTest {
  name = "dox-populi-itest";

  # Worst-case sum of subtest deadlines (3 x 600s + 1500s) plus boot and
  # deploy approaches the driver's default 3600s global timeout.
  globalTimeout = 5400;

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

    # Best-effort tick compression via the server CLI — a failure here
    # only means slower ticks, never a failed test.
    status, out = machine.execute("${setTickDuration} 2>&1")
    print(f">>> system.setTickDuration(100) via CLI (status {status}): {out.strip()}")

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

    with subtest("harvester emits sinksFull when all energy sinks are full"):
        # Once every sink (spawn + extensions) fills and the harvester's
        # store is full, emitEvent must emit "sinksFull" (not "storeFull")
        # and the FSM must land in "harvesting" (idle at source). This is
        # the real game runtime proving the compound event logic works.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollHarvesterSinksFull} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: harvester correctly idles on sinksFull")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for harvester sinksFull event")
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

    with subtest("extension gets built"):
        # Tutorial-3 end-to-end proof: the controller reaches RCL 2, the
        # shell places the spec-driven extension site, and the builder
        # hauls 3000 energy into it until the structure exists. The long
        # deadline covers the un-compressed 1s tick worst case.
        deadline = time.time() + 1500
        while True:
            status, out = machine.execute("${pollExtensionBuilt} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: extension built")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the extension to be built")
            time.sleep(2)
  '';
}
