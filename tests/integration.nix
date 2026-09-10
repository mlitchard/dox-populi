# Integration test. Boots a VM, runs the nix-vendored Screeps server,
# deploys with the production deploy-local script, then watches the
# section-1 loop: the harvester spawns, harvests, and delivers energy
# back to the spawn. Probes go through the server CLI: the db view,
# plus the per-creep Memory.trace logs the harness keeps.
{ testers
, writeShellScript
, curl
, netcat-openbsd
, # The flake's apps.*.program entries, the same scripts users run.
  serverProgram
, deployProgram
, # Milliseconds per tick, pushed to the server CLI. Comes from the
  # flake's tickMs binding so the test and the dev server share one
  # setting.
  tickMs ? 100
, # VM sizing; the flake passes its hardware contract's values.
  memorySize ? 32768
, cores ? 8
}:
let
  email = "itest";
  password = "itest-password";
  url = "http://127.0.0.1:21025";

  # -------------------------------------------------------------------
  # CLI scripts. Port 21026 is a JS REPL over TCP with the storage.db
  # collections in scope. Scripts keep the connection open while the
  # REPL evaluates (`(printf 'CMD\n'; sleep 3) | nc -N -w 6`) and grep
  # for a marker string returned by the final .then. Nothing writes.
  # -------------------------------------------------------------------

  # Succeeds once the itest account owns at least one creep.
  pollHarvesterExists = writeShellScript "poll-harvester-exists" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].find({type: "creep", user: u._id})).then(cs => "CREEPS:" + cs.length + ":").catch(e => "ERR:" + (e && e.message || e))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    N=$(printf '%s' "$OUT" | grep -o 'CREEPS:[0-9]*' | grep -o '[0-9]*' || echo "")
    echo "creeps owned: ''${N:-unknown} ($OUT)"
    [ -n "$N" ] && [ "$N" -ge 1 ]
  '';

  # Succeeds once the spawn's stored energy rises between two polls:
  # the harvester delivered. Spawning costs energy first, so a rise
  # above the previous reading witnesses harvest + transfer, never
  # just the initial 300.
  pollSpawnEnergy = writeShellScript "poll-spawn-energy" ''
    set -euo pipefail
    STATE=/tmp/itest-spawn-energy
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})).then(s => "ENERGY:" + (s && s.store && s.store.energy) + ":").catch(e => "ERR:" + (e && e.message || e))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    E=$(printf '%s' "$OUT" | grep -o 'ENERGY:[0-9]*' | grep -o '[0-9]*' || echo "")
    [ -n "$E" ] || { echo "no spawn energy reading yet ($OUT)"; exit 1; }
    echo "spawn energy: $E"
    if [ -f "$STATE" ] && [ "$E" -gt "$(cat "$STATE")" ]; then
      echo "spawn acquired energy"
      exit 0
    fi
    printf '%s\n' "$E" > "$STATE"
    exit 1
  '';

  # Succeeds once a successful transfer is on record in Memory.trace:
  # the harvester delivered, witnessed by the same log the console
  # probes read.
  pollDeliveryTrace = writeShellScript "poll-delivery-trace" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.env.get(storage.env.keys.MEMORY + u._id)).then(m => { var trace = JSON.parse(m || "{}").trace || {}; var n = 0; Object.keys(trace).forEach(k => trace[k].forEach(e => { if (e.action === "transfer" && e.rc === 0) n += 1; })); return "DELIVERIES:" + n + ":"; }).catch(e => "ERR:" + (e && e.message || e))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    N=$(printf '%s' "$OUT" | grep -o 'DELIVERIES:[0-9]*' | grep -o '[0-9]*' || echo "")
    echo "transfers on record: ''${N:-unknown} ($OUT)"
    [ -n "$N" ] && [ "$N" -ge 1 ]
  '';

  setTickDuration = writeShellScript "set-tick-duration" ''
    printf 'system.setTickDuration(${toString tickMs})\n' \
      | ${netcat-openbsd}/bin/nc -q 2 127.0.0.1 21026
  '';
in
testers.runNixOSTest {
  name = "dox-populi-itest";

  # Worst-case sum of the subtest deadlines plus boot and deploy.
  globalTimeout = 3000;

  nodes.machine = {
    # The server runs storage, backend, and engine child processes
    # plus runner and processor workers, and holds the whole world db
    # in memory (LokiJS).
    virtualisation = { inherit memorySize cores; };

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

    with subtest("harvester spawns"):
        # Explicit poll loop so every observation is visible in the log.
        deadline = time.time() + 600
        while True:
            status, out = machine.execute("${pollHarvesterExists} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: harvester spawned")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the harvester to spawn")
            time.sleep(2)

    with subtest("spawn acquires energy"):
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

    with subtest("delivery lands in Memory.trace"):
        deadline = time.time() + 60
        while True:
            status, out = machine.execute("${pollDeliveryTrace} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: transfer recorded in Memory.trace")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for a transfer in Memory.trace")
            time.sleep(2)
  '';
}
