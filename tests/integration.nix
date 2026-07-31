# Integration test : boot a VM, start the
# private Screeps server (nix-vendored npm package), provision an
# account + push main.js + place Spawn1 (the production deploy-local
# script, unchanged), then poll the memory endpoint until (1) the spawn
# acquires energy (harvester works), (2) the controller gains progress
# (upgrader works), (3) an extension is built (builder + spec-driven
# extension placement work), and (4) the colony survives generational
# turnover (creeps age out, replacements respawn, progress continues).
# Fully pure — runs in plain `nix flake check`.
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
, # ms per tick pushed to the server CLI — wired from the flake's
  # tickMs binding so the test and the dev server share one knob.
  tickMs ? 100
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

  # One-shot probe: read Memory.stats.deaths (cumulative, monotonic).
  # Succeeds once at least one creep has died of old age (lifespan is
  # 1500 ticks) — the precondition for the generational-turnover claim.
  pollFirstDeath = writeShellScript "poll-first-death" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.deaths" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.deaths in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    D=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "deaths: $D"
    [ "$D" -ge 1 ]
  '';

  # One-shot reader: print Memory.stats.controllerProgress (just the
  # number) so the test driver can record a baseline at death detection.
  readControllerProgress = writeShellScript "read-controller-progress" ''
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
      *) echo "no stats.controllerProgress in memory (got: $DATA)" >&2; exit 1 ;;
    esac
    printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat
  '';

  # One-shot probe: read Memory.stats.roleCounts / births / deaths.
  # Succeeds when every role is back at desired strength AND enough
  # births have happened to prove respawn (not just the initial wave).
  # Oracle values mirror dox/creeps.dox spawnQueue: harvester desired: 2,
  # upgrader desired: 1, builder desired: 2 — 5 creeps total. Roles with
  # zero live creeps have NO key in roleCounts, hence the `// 0` default.
  # births >= deaths + 5 is the monotonic respawn proof: the initial
  # spawn wave accounts for 5 births, so being back at full strength
  # after >= 1 death forces at least one replacement birth.
  pollRolesRecovered = writeShellScript "poll-roles-recovered" ''
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
    COUNTS=$(decode stats.roleCounts)
    BIRTHS=$(decode stats.births)
    DEATHS=$(decode stats.deaths)
    echo "roleCounts: $COUNTS (births: $BIRTHS, deaths: $DEATHS)"
    [ "$COUNTS" != absent ] && [ "$BIRTHS" != absent ] && [ "$DEATHS" != absent ]
    printf '%s' "$COUNTS" | ${jq}/bin/jq -e \
      --argjson births "$BIRTHS" --argjson deaths "$DEATHS" '
        ((.harvester // 0) >= 2)
        and ((.upgrader // 0) >= 1)
        and ((.builder // 0) >= 2)
        and ($births >= $deaths + 5)
      ' > /dev/null
  '';

  # One-shot probe: read Memory.stats.creeps and succeed when any live
  # creep has parts == 5 — the heavy tier from dox/creeps.dox
  # (heavyWorkerBody = [work, work, carry, move, move], cost 350 = spawn
  # 300 + 1 extension 50). It only spawns when energyAvailable covers
  # 350, so its appearance proves tutorial-3's extension capacity is
  # actually being SPENT on post-death replacements.
  pollHeavyCreep = writeShellScript "poll-heavy-creep" ''
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
    printf '%s' "$JSON" | ${jq}/bin/jq -e '
      to_entries | map(select(.value.parts == 5)) | length > 0
    ' > /dev/null
  '';

  # One-shot probe: controllerProgress strictly above the baseline
  # recorded at death detection ($1) — upgrading continued after the
  # funeral, so the colony as a whole never stalled.
  pollProgressAfterDeath = writeShellScript "poll-progress-after-death" ''
    set -euo pipefail
    BASE="$1"
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.controllerProgress" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.controllerProgress in memory (got: $DATA)" >&2; exit 1 ;;
    esac
    P=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "controller progress: $P (baseline at death: $BASE)"
    [ "$P" -gt "$BASE" ]
  '';

  # Tick compression: the extension needs RCL 2 (200 controller progress)
  # and then 3000 build-energy — far too slow at the default 1s tick. The
  # server CLI on 21026 accepts system.setTickDuration(ms); best-effort
  # (the test still passes at 1s ticks, just near the deadline).
  setTickDuration = writeShellScript "set-tick-duration" ''
    printf 'system.setTickDuration(${toString tickMs})\n' \
      | ${netcat-openbsd}/bin/nc -q 2 127.0.0.1 21026
  '';
in
testers.runNixOSTest {
  name = "dox-populi-itest";

  # Worst-case sum of subtest deadlines (3 x 600s + 1500s tutorial-1..3,
  # plus 900s + 600s + 600s + 300s for the turnover phases = 5700s) plus
  # boot and deploy far exceeds the driver's default 3600s global timeout.
  globalTimeout = 7200;

  nodes.machine = {
    # Server spawns storage/backend/engine children plus runner/processor
    # workers; the world db is an in-memory LokiJS.
    virtualisation = {
      memorySize = 32768;
      cores = 8;
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
    print(f">>> system.setTickDuration(${toString tickMs}) via CLI (status {status}): {out.strip()}")

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

    with subtest("generational turnover: the colony outlives its creeps"):
        # Tutorial-4 end-to-end proof: creeps die of old age (1500-tick
        # lifespan) and the colony repairs itself unattended — every role
        # respawns to desired strength, replacement bodies spend the
        # extension's capacity (heavy 5-part tier), and controller
        # progress keeps rising after the funeral.

        # Phase 1: wait for the first natural death. 1500 ticks after the
        # first spawn is ~150s at compressed 100ms ticks; the earlier
        # subtests have already burned thousands of ticks, so the first
        # funeral may well be in the books before we even start —
        # `deaths >= 1` on the cumulative counter handles both cases. The
        # 900s deadline covers a late start at un-compressed 1s ticks.
        deadline = time.time() + 900
        while True:
            status, out = machine.execute("${pollFirstDeath} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> first natural death observed")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the first creep death")
            time.sleep(2)

        # Phase 2: record controller progress at death detection — the
        # baseline that phase 5 must strictly exceed.
        baseline = int(machine.succeed("${readControllerProgress}").strip())
        print(f">>> controller progress at death detection: {baseline}")

        # Phase 3: every role back to desired strength (2/1/2 per the
        # spec's spawnQueue) and births >= deaths + 5, proving respawn
        # rather than leftover initial spawning. Replacements cost at
        # most 350 energy each against a harvester-fed spawn; 600s
        # matches the earlier steady-state subtest deadlines.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollRolesRecovered} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: all roles recovered to desired strength via respawn")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for role counts to recover after death")
            time.sleep(2)

        # Phase 4: some live creep has the heavy 5-part body — sinks were
        # full at death time, so the first post-death spawn should afford
        # the 350-cost tier. Likely coincides with phase 3's respawns.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollHeavyCreep} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: heavy-tier (5-part) creep spawned — extension capacity spent")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for a heavy-tier creep")
            time.sleep(2)

        # Phase 5: controller progress strictly above the phase-2
        # baseline — the upgrader pipeline survived the turnover.
        deadline = time.time() + 300
        while True:
            status, out = machine.execute(f"${pollProgressAfterDeath} {baseline} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: controller progress rose after the funeral")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for controller progress after death")
            time.sleep(2)
  '';
}
