# Integration test. Boots a VM, runs the nix-vendored Screeps server,
# deploys with the production deploy-local script, then polls the
# memory endpoint through the tutorial milestones and into the war.
# armWarConditions performs the single write that starts the war;
# everything after it only observes and paces ticks.
{ testers
, writeShellScript
, curl
, jq
, gzip
, coreutils
, netcat-openbsd
, # The flake's apps.*.program entries, the same scripts users run.
  serverProgram
, deployProgram
, # Milliseconds per tick, pushed to the server CLI. Comes from the
  # flake's tickMs binding so the test and the dev server share one
  # setting.
  tickMs ? 100
}:
let
  email = "itest";
  password = "itest-password";
  url = "http://127.0.0.1:21025";

  # The memory endpoint returns each value gzipped and base64-encoded,
  # prefixed with "gz:". Every probe below strips the prefix and
  # decodes.
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

  # Succeeds once Memory.trace shows a creep entering "supporting" on
  # a full-store, sinks-full event. Only the harvester machine has a
  # state named "supporting", so no other role can trip this.
  pollHarvesterSupporting = writeShellScript "poll-harvester-supporting" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=trace" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no trace in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    T=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "supporting trace: $(printf '%s' "$T" | ${jq}/bin/jq -c \
      '[.[] | .[] | select(.fsm == "supporting")]')"
    printf '%s' "$T" | ${jq}/bin/jq -e '
      [.[] | .[] | select((.event | startswith("fullSinksFull"))
                          and .fsm == "supporting")]
      | length > 0
    ' > /dev/null
  '';

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

  # The 2/1/2 thresholds must match spawnQueue in dox/creeps.dox. A
  # role with no live creeps is missing from roleCounts entirely, so
  # each lookup defaults to 0. The initial wave is 5 births, so
  # births >= deaths + 5 holds only if every death was answered with
  # a replacement spawn.
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

  # A 5-part creep is the heavyWorkerBody tier and must match its
  # definition in dox/creeps.dox. Its 350 energy cost only fits once
  # the extension adds capacity beyond the spawn's 300.
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

  # $1 is the controllerProgress baseline recorded when the death was
  # detected.
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

  # -------------------------------------------------------------------
  # CLI scripts. Port 21026 is a JS REPL over TCP with the storage.db
  # collections in scope. Scripts that need the response keep the
  # connection open while the REPL evaluates
  # (`(printf 'CMD\n'; sleep 3) | nc -N -w 6`) and grep for a marker
  # string returned by the final .then. armWarConditions is the only
  # script that writes.
  # -------------------------------------------------------------------

  # Arms the war in one expression, three writes. Sets the controller
  # to level 3 (towers become legal to own) and nulls safeMode, since
  # the raid mod defers any room whose safeMode is still a number.
  # Sets every source's invaderHarvested to 50000, which must match
  # raidPolicy.goal in shell/raidmod.ts. Inserts a tower two tiles
  # southwest of the spawn holding 1000 energy, which must match
  # towerFullEnergy in shell/raidmod.ts; the insert is skipped when a
  # tower already exists, so the retry loop can't stack towers.
  armWarConditions = writeShellScript "arm-war-conditions" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => Promise.all([u, storage.db["rooms.objects"].findOne({type: "controller", user: u._id}), storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})])).then(ucs => Promise.all([storage.db["rooms.objects"].update({_id: ucs[1]._id}, {$set: {level: 3, progress: 0, safeMode: null}}), storage.db["rooms.objects"].update({room: ucs[1].room, type: "source"}, {$set: {invaderHarvested: 50000}}), storage.db["rooms.objects"].findOne({type: "tower", user: ucs[0]._id}).then(tw => tw || storage.db["rooms.objects"].insert({type: "tower", room: ucs[2].room, x: ucs[2].x - 2, y: ucs[2].y + 2, user: ucs[0]._id, hits: 3000, hitsMax: 3000, store: {energy: 1000}, storeCapacityResource: {energy: 1000}, notifyWhenAttacked: false, actionLog: {attack: null, heal: null, repair: null}}))]).then(() => Promise.all([storage.db["rooms.objects"].findOne({_id: ucs[1]._id}), storage.db["rooms.objects"].find({type: "tower", user: ucs[0]._id})]))).then(ct => "ARMED:" + JSON.stringify({room: ct[0].room, level: ct[0].level, safeMode: ct[0].safeMode, towers: ct[1].map(t => ({x: t.x, y: t.y, e: t.store.energy}))})).catch(e => "ERR:" + (e && e.message || e))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    echo "$OUT"
    case "$OUT" in
      *ARMED:*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';

  # The raid mod names every raider it spawns "raider-g<gameTime>-".
  # Raider traces accumulate in memory:raiders and are never cleared,
  # so this probe still succeeds after the raiders themselves are
  # dead.
  pollNaturalRaid = writeShellScript "poll-natural-raid" ''
    set -euo pipefail
    CMD='storage.env.get("memory:raiders").then(m => "NATRAID:" + ((("" + (m || "")).indexOf("raider-g") >= 0) ? "YES" : "NO")).catch(e => "ERR:" + (e && e.message || e))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    echo "$OUT"
    case "$OUT" in
      *NATRAID:YES*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';

  pollControllerLevel3 = writeShellScript "poll-controller-level3" ''
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
    L=$(decode stats.controllerLevel)
    echo "controller level: $L (progress: $(decode stats.controllerProgress))"
    [ "$L" != absent ] && [ "$L" -ge 3 ]
  '';

  pollTowerBuilt = writeShellScript "poll-tower-built" ''
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
    N=$(decode stats.towersBuilt)
    echo "towers built: $N (RCL: $(decode stats.controllerLevel), towers: $(decode stats.towers))"
    [ "$N" != absent ] && [ "$N" -ge 1 ]
  '';

  # The 1000 threshold must match towerRefillTarget in dox/creeps.dox.
  # It is also the energy level the raid mod requires before it will
  # raid the room.
  pollTowerFull = writeShellScript "poll-tower-full" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.towers" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.towers in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    JSON=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "towers: $JSON"
    printf '%s' "$JSON" | ${jq}/bin/jq -e '
      [.[] | select(.energy >= 1000)] | length > 0
    ' > /dev/null
  '';

  # Prints one CLI snapshot of the fight: each raider's position,
  # hits, fatigue, and actionLog.attack (the engine writes that field
  # only when an attack intent actually processes); the spawn's hits
  # and actionLog.attacked, which stay readable after the raiders
  # die; and the first 4000 characters of the raiders user's memory,
  # enough to hold a full escalation.
  forensicsRaiders = writeShellScript "forensics-raiders" ''
    set -euo pipefail
    CMD='Promise.all([storage.db["rooms.objects"].find({user: "raiders"}), storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})), storage.env.get("memory:raiders")]).then(rsm => "FORENSICS:" + JSON.stringify({raiders: rsm[0].map(c => ({n: c.name, r: c.room, x: c.x, y: c.y, hits: c.hits, fatigue: c.fatigue, atk: c.actionLog && c.actionLog.attack})), spawn: rsm[1] && {r: rsm[1].room, x: rsm[1].x, y: rsm[1].y, hits: rsm[1].hits, hitsMax: rsm[1].hitsMax, attacked: rsm[1].actionLog && rsm[1].actionLog.attacked}, mem: rsm[2] && String(rsm[2]).slice(0, 4000)}))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 2) | ${netcat-openbsd}/bin/nc -N -w 5 127.0.0.1 21026 || true)
    echo "$OUT" | grep -o "FORENSICS:.*" || echo "$OUT"
  '';

  # stats.combat.damageTaken is a running total the shell builds by
  # diffing hits each tick, so damage that lands and is healed within
  # a single tick still counts.
  readDamageTaken = writeShellScript "read-damage-taken" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.combat.damageTaken" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.combat.damageTaken in memory (got: $DATA)" >&2; exit 1 ;;
    esac
    printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat
  '';

  setTickDuration = writeShellScript "set-tick-duration" ''
    printf 'system.setTickDuration(${toString tickMs})\n' \
      | ${netcat-openbsd}/bin/nc -q 2 127.0.0.1 21026
  '';
in
testers.runNixOSTest {
  name = "dox-populi-itest";

  # Worst-case sum of all subtest deadlines (~8100s) plus boot and
  # deploy.
  globalTimeout = 9000;

  nodes.machine = {
    # The server runs storage, backend, and engine child processes
    # plus runner and processor workers, and holds the whole world db
    # in memory (LokiJS).
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

    # Best-effort tick compression via the server CLI. A failure here
    # only means slower ticks.
    status, out = machine.execute("${setTickDuration} 2>&1")
    print(f">>> system.setTickDuration(${toString tickMs}) via CLI (status {status}): {out.strip()}")

    # The raid mod is loaded from boot via mods.json, but it only
    # raids rooms holding a fully loaded tower (raidPolicy.minTowers
    # and towerFullEnergy in shell/raidmod.ts), so the tutorial
    # subtests run undisturbed until the arming write inserts that
    # tower.

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

    with subtest("full harvester under saturated sinks moves to supporting"):
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollHarvesterSupporting} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: full harvester supports the controller under saturation")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for harvester fullSinksFull*/supporting")
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
        # 1500s covers the worst case of un-compressed 1s ticks.
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
        # Phase 1: wait for the first natural death. The deaths
        # counter is cumulative, so a death before this subtest also
        # counts. 900s covers a late start at un-compressed 1s ticks.
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

        # Phase 2: record the baseline that phase 5 must strictly
        # exceed.
        baseline = int(machine.succeed("${readControllerProgress}").strip())
        print(f">>> controller progress at death detection: {baseline}")

        # Phase 3: wait for every role to respawn back to desired
        # strength.
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

        # Phase 4: wait for a replacement spawned at the heavy 5-part
        # tier.
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

        # Phase 5: wait for progress to rise strictly above the
        # phase-2 baseline.
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

    with subtest("arming write seeds the war's start conditions"):
        # The retry loop only covers CLI hiccups; armWarConditions
        # documents what gets written.
        deadline = time.time() + 120
        while True:
            status, out = machine.execute("${armWarConditions} 2>&1")
            print(f">>> arm: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: war conditions seeded — RCL 3, safe mode off, raidGoal crossed, full tower standing")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out arming the war conditions via the CLI")
            time.sleep(5)
        # Waiting until the shell reports RCL 3 proves the world
        # accepted the write.
        deadline = time.time() + 120
        while True:
            status, out = machine.execute("${pollControllerLevel3} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: shell observes RCL 3")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the shell to observe the seeded RCL 3")
            time.sleep(2)

    with subtest("shell observes the seeded tower, standing and full"):
        # These polls prove the brain sees the seeded tower:
        # stats.towersBuilt counts owned towers and stats.towers
        # reports their energy.
        deadline = time.time() + 180
        while True:
            status, out = machine.execute("${pollTowerBuilt} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: shell observes the tower")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the shell to observe the seeded tower")
            time.sleep(2)
        deadline = time.time() + 180
        while True:
            status, out = machine.execute("${pollTowerFull} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower reads full (energy >= 1000) — fair-fight bar met")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the tower to read full energy")
            time.sleep(2)

    with subtest("the world makes war and draws first blood"):
        # With every gate open, genRaiders launches an escalating
        # wave on each 10s cron check. The subtest asserts one thing:
        # cumulative damageTaken reaches 1. In a live run the fresh
        # tower wiped wave 1 and the first damage landed in wave 2.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollNaturalRaid} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: mod-raised raiders (raider-g*) latched in the flight recorder")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the raid mod to open the war")
            time.sleep(10)
        for i in range(3):
            status, out = machine.execute("${forensicsRaiders} 2>&1")
            print(f">>> forensics[war.{i}]: {out.strip()}")
            time.sleep(1)
        deadline = time.time() + 1200
        while True:
            status, out = machine.execute("${readDamageTaken} 2>&1")
            damage = int(out.strip()) if status == 0 and out.strip().isdigit() else -1
            print(f">>> damageTaken: {out.strip()}")
            if damage >= 1:
                print(">>> SUCCESS: first blood drawn — the offense is real, no hand on the scale")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — recorder dump for root cause:")
                status, out = machine.execute("${forensicsRaiders} 2>&1")
                print(f">>> forensics[final]: {out.strip()}")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception(
                    "relentless waves kept landing but drew no blood — "
                    "the offense path is dead; the trace above names the statute"
                )
            time.sleep(5)

  '';
}
