# Integration test : boot a VM, start the
# private Screeps server (nix-vendored npm package), provision an
# account + push main.js + place Spawn1 (the production deploy-local
# script, unchanged), then poll the memory endpoint through the
# tutorial 1-5 story: (1) the spawn acquires energy (harvester works),
# (2) the controller gains progress (upgrader works), (3) an extension
# is built (builder + spec-driven extension placement work), (4) the
# colony survives generational turnover (creeps age out, replacements
# respawn, progress continues), and (5) the war arc. Surgery doctrine
# (user ruling 2026-08-02, amending the total no-surgery ruling): the
# test SEEDS the war's start conditions in ONE arming write — the
# controller to RCL 3, safe mode off, the harvested counter past
# raidGoal, and the TOWER ITSELF standing at the spec's first
# towerOffsets cell with a full magazine — because the natural climb
# (45k upgrade energy + ~20000 safe-mode ticks + a 5000-energy build)
# proves only patience, not war. Everything AFTER the arming write is
# observation and tick pacing, nothing else. With a FULL tower
# standing, every gate is open at once, and the raid MOD
# opens the RELENTLESS WAR (spec raid-law): an escalating wave on
# every cron check, forever — the durability test of a single tower.
# The test asserts exactly one thing about that war, by user ruling:
# FIRST BLOOD (cumulative damageTaken >= 1) — and no more. How long
# the tower stands against the unending escalation is the live
# server's show; an itest cannot wait for a doom that arrives by
# arithmetic.
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

  # One-shot probe: Memory.trace holds an entry with a fullSinksFull*
  # event (store full AND every sink saturated — both fullSinksFullSite
  # and fullSinksFullNoSite qualify) whose fsm is "supporting" — proof
  # that the product event vocabulary observes the compound saturation
  # FACT in the real game runtime AND the full+saturated->assist policy
  # fires. State names are disjoint across machines, so fsm=="supporting"
  # can only be a harvester (the spec's namespace rule doubles as the
  # role filter). The flight recorder latches the moment durably — the
  # old stats.creeps version of this probe had to catch a ~1-2s
  # transient window and passed by recurrence, not by proof. This probe
  # runs BEFORE the tower exists, so saturation here means spawn +
  # extension only — reachability unchanged from tutorial 4.
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

  # -------------------------------------------------------------------
  # CLI scripts. The server CLI on 21026 is a JS REPL over TCP with
  # the storage.db collections in scope. setTickDuration below uses
  # fire-and-forget `nc -q 2`; the rest need the RESPONSE (both for
  # the success marker and for the log), so they use the session
  # pattern `(printf 'CMD\n'; sleep 3) | nc -N -w 6` — hold the write
  # side open long enough for the REPL to evaluate, then read until the
  # server closes or -w times out. Each script is ONE chained-promise
  # expression whose final .then returns a marker string the shell
  # greps for. Surgery doctrine (user ruling 2026-08-02): exactly ONE
  # script writes — armWarConditions, the war arc's seeded start.
  # Every other CLI script READS ONLY, and the raid MOD alone raises
  # every raider that ever appears.
  # -------------------------------------------------------------------

  # The arming write — the war arc's seeded start conditions, in one
  # expression (user ruling: lift the gates, BUILD THE TOWER, start
  # the wave — all three seeded):
  #   - controller to RCL 3 (tower legality) with safe mode cleared
  #     (typeof null is not "number", so the mod's deferral passes)
  #   - every source gets invaderHarvested 50000 — the raid law's
  #     goal (mirrors dox/invader raidPolicy.goal; amend together);
  #     RELENTLESS WAR never resets it, so the threshold stays
  #     crossed forever
  #   - a TOWER standing at the spec's first towerOffsets cell
  #     (offsetSouthwest: spawn-2,+2 — amend with the spec), owned by
  #     the itest user, full magazine (store.energy 1000 =
  #     towerFullEnergy — the fair-fight bar) — modern store shape,
  #     TOWER_HITS 3000. Insert is idempotent (skipped if any tower
  #     already stands) so the retry loop can't stack towers.
  # After this write EVERY gate is open: genRaiders owes a wave
  # within one cron check.
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

  # Natural-raid witness: the raid MOD (not the test) inserted raiders.
  # Mod-spawned raiders carry the raider-g<gameTime>- name prefix, and
  # the invader shell's flight recorder latches every raider's trace in
  # the raiders user's memory forever (append-on-change, NO dead
  # pruning) — so this probe survives the one-tick-transient trap: the
  # corpses clear in ticks, the tombstone talks.
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

  # One-shot probe: stats.controllerLevel >= 3 — the shell OBSERVES
  # the seeded RCL 3 (towers unlock at 3): telemetry confirmation
  # that the arming write landed in the world the brain actually
  # sees, not just in the db.
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

  # One-shot probe: stats.towersBuilt >= 1 — the shell observes the
  # seeded tower (FIND_MY_STRUCTURES count) and the tower machine is
  # live. towersBuilt/RCL/towers printed every poll for diagnosis.
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

  # One-shot probe: some tower in stats.towers reads FULL (>= 1000 =
  # towerRefillTarget, the raid law's fair-fight bar — amend together).
  # Under the amended refill law a below-full tower is an ordinary
  # energy sink, so delivery tops it all the way up; the moment this
  # probe passes, the last gate is open and the war is due within one
  # raid-mod cron check.
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

  # Forensic witness, not a probe: one CLI snapshot of the fight —
  # every raiders-user creep's room/position/hits/fatigue/
  # actionLog.attack (the engine writes actionLog.attack only when an
  # attack intent actually PROCESSES), the itest spawn's hits +
  # actionLog.attacked (persistent evidence that survives the raiders'
  # corpses), and the raiders user's memory: Memory.raiders (the live
  # fsm) plus Memory.trace — the flight recorder, one {t, event, fsm,
  # action, rc} line per change per raider, latched past death. The
  # 4000-char window fits the recorder for a full escalation. Printed
  # around each raid subtest so a failure carries its own diagnosis
  # instead of a bare timeout — and a PASSING arc documents what the
  # raiders' FSMs were doing.
  forensicsRaiders = writeShellScript "forensics-raiders" ''
    set -euo pipefail
    CMD='Promise.all([storage.db["rooms.objects"].find({user: "raiders"}), storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})), storage.env.get("memory:raiders")]).then(rsm => "FORENSICS:" + JSON.stringify({raiders: rsm[0].map(c => ({n: c.name, r: c.room, x: c.x, y: c.y, hits: c.hits, fatigue: c.fatigue, atk: c.actionLog && c.actionLog.attack})), spawn: rsm[1] && {r: rsm[1].room, x: rsm[1].x, y: rsm[1].y, hits: rsm[1].hits, hitsMax: rsm[1].hitsMax, attacked: rsm[1].actionLog && rsm[1].actionLog.attacked}, mem: rsm[2] && String(rsm[2]).slice(0, 4000)}))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 2) | ${netcat-openbsd}/bin/nc -N -w 5 127.0.0.1 21026 || true)
    echo "$OUT" | grep -o "FORENSICS:.*" || echo "$OUT"
  '';

  # One-shot reader: print stats.combat.damageTaken (just the number) —
  # the FIRST-BLOOD test, the war arc's only assertion (user ruling
  # 2026-08-01: first blood and no more). Cumulative and latched by the
  # shell's tick diff, so damage that lands and heals inside one tick
  # still counts forever. Fails (exit 1) only if the stat is absent.
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

  # Worst-case sum of subtest deadlines: tutorial-1..3 (3 x 600s +
  # 1500s) plus the turnover phases (900s + 600s + 600s + 300s) =
  # 5700s, plus the SEEDED war arc: arming write 120s + RCL 3
  # observation 120s + tower observation 180s + 180s, then the
  # relentless war's single assertion: war opens 600s (every gate
  # pre-opened; one 10s cron check away) + first blood 1200s (waves
  # land every 10s, escalating — live evidence puts blood at wave 2)
  # ≈ 2400s of post-turnover deadlines — ≈ 8100s total, plus boot
  # and deploy. Deadlines only accrue on the FAILURE path (each phase
  # exits the moment its probe passes), but the global timeout must
  # cover the honest slow run.
  globalTimeout = 9000;

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

    # No sterilizer, no dial. The raid mod is LIVE from boot
    # (mods.json), and the FAIR-FIGHT CLAUSE is the only shield the
    # early phases get: a room with no FULL tower is not raid-eligible
    # (raidPolicy.minTowers + towerFullEnergy), so the tutorial acts
    # run unmolested until the arming write seeds the full tower and
    # opens every gate at once.

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
        # Once every sink (spawn + extension — no tower exists yet) fills
        # and the harvester's store is full, emitEvent must emit a
        # fullSinksFull* product event (the compound saturation FACT,
        # Site or NoSite alike) and the FSM must land in "supporting"
        # (action=upgrade — the full+saturated->assist policy). This is
        # the real game runtime proving the product event vocabulary.
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
        # first spawn is short at compressed (tickMs) ticks; the earlier
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

    with subtest("arming write seeds the war's start conditions"):
        # User ruling 2026-08-02: the test STARTS the war arc with the
        # necessary conditions instead of grinding the natural climb
        # (45k upgrade energy + ~20000 safe-mode ticks proved only
        # patience). ONE write: controller to RCL 3 with safe mode
        # cleared, sources' invaderHarvested past raidGoal. The short
        # retry loop covers CLI hiccups, not world time.
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
        # The shell must OBSERVE the seeded level (stats.controllerLevel
        # is telemetry, not db state) — proves the world took the write.
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
        # The arming write seeded the tower (spec's first towerOffsets
        # cell, full magazine). These polls prove the BRAIN sees it:
        # stats.towersBuilt counts FIND_MY_STRUCTURES towers and
        # stats.towers carries its energy — the tower machine is now
        # running the spec's tower FSM over a real structure. Full
        # tower == fair-fight bar: the war's last gate is open. The
        # refill law keeps it topped up between waves (below
        # towerRefillTarget = ordinary sink; latch = priority only).
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
        # The raid MOD opens this war, or nobody does. Every gate is
        # open — the arming write cleared safe mode and crossed
        # raidGoal, the previous subtest proved a FULL tower stands —
        # so genRaiders opens the RELENTLESS WAR within one cron check
        # (checkSeconds 10): an escalating wave on every check (the
        # harvested counter never resets, live raiders never hold off
        # the next wave). The war arc asserts EXACTLY ONE THING, by
        # user ruling (2026-08-01): FIRST BLOOD — cumulative
        # damageTaken >= 1. Live evidence (W9N8): a fresh tower
        # clean-sweeps wave 1, and blood lands from wave 2 on; under
        # the amended refill law the tower is topped back to full
        # between waves, so the escalation actually continues (the
        # first latch-gated law deadlocked at 990 and wave 2 never
        # came). Everything past first blood — how long the single
        # tower stands against the unending escalation — is the live
        # server's show, not an itest deadline.
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
        # Forensic witness: snapshot the raiders mid-fight — position,
        # hits, fatigue, actionLog.attack (set only when an attack
        # intent PROCESSES), the spawn's hits + actionLog.attacked, and
        # the raiders user's memory (fsm + flight recorder). The
        # corpses clear in ticks; these lines are the cross-examination
        # that survives.
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
