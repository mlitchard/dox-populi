# Integration test : boot a VM, start the
# private Screeps server (nix-vendored npm package), provision an
# account + push main.js + place Spawn1 (the production deploy-local
# script, unchanged), then poll the memory endpoint through the
# tutorial 1-5 story: (1) the spawn acquires energy (harvester works),
# (2) the controller gains progress (upgrader works), (3) an extension
# is built (builder + spec-driven extension placement work), (4) the
# colony survives generational turnover (creeps age out, replacements
# respawn, progress continues), and (5) the defense arc — world surgery
# over the server CLI forces RCL 3, the tower gets built and fed, an
# inserted invader dies to it, CLI-inflicted battle damage gets
# repaired, and the economy keeps beating afterward.
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
  # {role, event, fsm, action, parts} written by the shell every tick.
  # Succeeds when a harvester's event carries the fullSinksFull* prefix
  # (store full AND every sink saturated — both fullSinksFullSite and
  # fullSinksFullNoSite qualify) while its fsm is "supporting" — proof
  # that the product event vocabulary observes the compound saturation
  # FACT in the real game runtime AND the full+saturated->assist policy
  # (harvester supporting state, action=upgrade) fires. This probe runs
  # BEFORE the tower exists, so saturation here means spawn + extension
  # only — reachability unchanged from tutorial 4.
  pollHarvesterSupporting = writeShellScript "poll-harvester-supporting" ''
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
    # Succeed if ANY harvester observes fullSinksFull* and supports.
    printf '%s' "$JSON" | ${jq}/bin/jq -e '
      to_entries | map(select(
        .value.role == "harvester"
        and (.value.event | startswith("fullSinksFull"))
        and .value.fsm == "supporting"
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

  # -------------------------------------------------------------------
  # Tutorial-5 world surgery. The server CLI on 21026 is a JS REPL over
  # TCP with the storage.db collections in scope. setTickDuration below
  # uses fire-and-forget `nc -q 2`; surgery needs the RESPONSE (both
  # for the success marker and for the log), so these use the session
  # pattern `(printf 'CMD\n'; sleep 3) | nc -N -w 6` — hold the write
  # side open long enough for the REPL to evaluate, then read until the
  # server closes or -w times out. Each script is ONE chained-promise
  # session: the itest user (usernameLower — screepsmod-auth stores
  # both username and usernameLower on register) resolves to their
  # spawn document, and the spawn's room names the surgery target — the
  # room is dynamic, never hardcoded. A marker string returned from the
  # final .then is the success signal the shell greps for.
  # -------------------------------------------------------------------

  # Raise the itest room's controller to RCL 3 (towers unlock at 3).
  # Field shapes verified against a real dev-world controller document
  # (.server-data/db.json): {room, type, x, y, level, progress,
  # downgradeTime, user, ...} — no progressTotal on the doc, so only
  # level + progress are $set (progress zeroed: level-3 progress
  # restarts from scratch).
  surgeryRcl3 = writeShellScript "surgery-rcl3" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})).then(s => storage.db["rooms.objects"].update({room: s.room, type: "controller"}, {$set: {level: 3, progress: 0}})).then(r => "RCL3-OK:" + JSON.stringify(r))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    echo "$OUT"
    case "$OUT" in
      *RCL3-OK:*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';

  # Insert a hostile creep owned by the stock seed's Invader NPC user
  # (user id "2" — verified against the dev-world db: users._id "2" has
  # username "Invader"). Document shape mirrors a REAL Invader-owned
  # creep from .server-data/db.json: type, name, room, x, y, user,
  # body[].{type,hits}, hits/hitsMax (100 per part), spawning, fatigue,
  # store, storeCapacity, notifyWhenAttacked, actionLog. Deliberately
  # omitted: ageTime (no natural death — the tower kill is the proof),
  # boost/strongholdId (stronghold-specific), meta/$loki (LokiJS adds
  # them on insert). Placed at spawn+(3,3): terrain risk is acceptable,
  # walls sit at room edges, not next to a spawn. The Invader user's
  # script is the empty seed stub, so the creep just stands there.
  surgeryInsertInvader = writeShellScript "surgery-insert-invader" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})).then(s => storage.db["rooms.objects"].insert({type: "creep", name: "invader-itest", room: s.room, x: s.x + 3, y: s.y + 3, user: "2", body: [{type: "attack", hits: 100}, {type: "move", hits: 100}], hits: 200, hitsMax: 200, spawning: false, fatigue: 0, store: {energy: 0}, storeCapacity: 0, notifyWhenAttacked: false, actionLog: {attacked: null, healed: null, attack: null, rangedAttack: null, rangedMassAttack: null, rangedHeal: null, harvest: null, heal: null, repair: null, build: null, say: null, upgradeController: null, reserveController: null}})).then(r => "INVADER-OK:" + JSON.stringify((r && r._id) || r))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    echo "$OUT"
    case "$OUT" in
      *INVADER-OK:*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';

  # Battle-damage the extension (hits 1000 -> 1; hits/hitsMax verified
  # on a real extension document). desiredExtensions is 1, so the
  # {room, type} query hits exactly the one structure.
  surgeryDamageExtension = writeShellScript "surgery-damage-extension" ''
    set -euo pipefail
    CMD='storage.db.users.findOne({usernameLower: "${email}"}).then(u => storage.db["rooms.objects"].findOne({type: "spawn", user: u._id})).then(s => storage.db["rooms.objects"].update({room: s.room, type: "extension"}, {$set: {hits: 1}})).then(r => "DAMAGE-OK:" + JSON.stringify(r))'
    OUT=$( (printf '%s\n' "$CMD"; sleep 3) | ${netcat-openbsd}/bin/nc -N -w 6 127.0.0.1 21026 || true)
    echo "$OUT"
    case "$OUT" in
      *DAMAGE-OK:*) exit 0 ;;
      *) exit 1 ;;
    esac
  '';

  # One-shot probe: stats.controllerLevel >= 3 — the RCL3 surgery took
  # effect and the shell observes the new level.
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

  # One-shot probe: stats.towersBuilt >= 1 — RCL 3 reached, the shell
  # placed the spec-driven tower site, and the builders hauled 5000
  # build-energy into it. towersBuilt/RCL/towers printed every poll
  # for diagnosis while the build is in flight.
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

  # One-shot probe: some tower in stats.towers has energy > 0 — the
  # harvesters treat the below-target tower as an energy sink and feed
  # it toward towerEnergyTarget (500).
  pollTowerFed = writeShellScript "poll-tower-fed" ''
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
      [.[] | select(.energy > 0)] | length > 0
    ' > /dev/null
  '';

  # One-shot probe: Memory.trace holds a tower entry with a hostile*
  # event, action=attack, rc=0 — durable proof the tower SAW the
  # invader and FIRED. stats.hostiles is a ONE-TICK transient here: a
  # point-blank tower deals 600 to the 200-hit invader, so the sighting
  # and the kill land in the same 50ms tick and no seconds-granularity
  # poll can be required to catch it (the first itest run proved this
  # by timing out on stats.hostiles while the colony hummed along).
  # The flight recorder appends on change and never forgets the
  # engagement. Tower-vocabulary entries (hostile*/calm*) are printed
  # each poll for diagnosis.
  pollTowerEngaged = writeShellScript "poll-tower-engaged" ''
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
    T=$(decode trace)
    if [ "$T" = absent ]; then echo "no trace in memory yet"; exit 1; fi
    echo "tower trace: $(printf '%s' "$T" | ${jq}/bin/jq -c \
      '[.[] | .[] | select(.event | startswith("hostile") or startswith("calm"))]') \
(hostiles now: $(decode stats.hostiles))"
    printf '%s' "$T" | ${jq}/bin/jq -e '
      [.[] | .[] | select((.event | startswith("hostile"))
                          and .action == "attack" and .rc == 0)]
      | length > 0
    ' > /dev/null
  '';

  # One-shot probe: stats.hostiles == 0 AFTER pollTowerEngaged latched
  # the attack — the threat is cleared. Together: the trace proves the
  # tower saw and shot (rc=0 on a 600-damage attack against 200 hits),
  # this proves nothing hostile remains. NPC creeps (user "2") never
  # cross room edges (engine tick.js exempts them), so "gone" = dead.
  pollInvaderDead = writeShellScript "poll-invader-dead" ''
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
    H=$(decode stats.hostiles)
    echo "hostiles: $H (towers: $(decode stats.towers))"
    [ "$H" != absent ] && [ "$H" -eq 0 ]
  '';

  # One-shot probe: colony integrity after the fight — every role still
  # at desired strength (2/1/2 per the spec's spawnQueue; roles with
  # zero live creeps have NO key, hence // 0). pollRolesRecovered minus
  # the births arithmetic: respawn was proven in the turnover subtest,
  # here only standing strength matters.
  pollColonyIntact = writeShellScript "poll-colony-intact" ''
    set -euo pipefail
    TOKEN=$(${curl}/bin/curl -sS -X POST "${url}/api/auth/signin" \
      -H "Content-Type: application/json" \
      --data '{"email":"${email}","password":"${password}"}' \
      | ${jq}/bin/jq -r '.token // empty')
    [ -n "$TOKEN" ]
    DATA=$(${curl}/bin/curl -sS -H "X-Token: $TOKEN" \
      "${url}/api/user/memory?path=stats.roleCounts" | ${jq}/bin/jq -r '.data // empty')
    case "$DATA" in
      gz:*) ;;
      *) echo "no stats.roleCounts in memory yet (got: $DATA)" >&2; exit 1 ;;
    esac
    COUNTS=$(printf '%s' "''${DATA#gz:}" | ${coreutils}/bin/base64 -d | ${gzip}/bin/zcat)
    echo "roleCounts: $COUNTS"
    printf '%s' "$COUNTS" | ${jq}/bin/jq -e '
      ((.harvester // 0) >= 2)
      and ((.upgrader // 0) >= 1)
      and ((.builder // 0) >= 2)
    ' > /dev/null
  '';

  # One-shot probe: Memory.trace holds a tower entry with a *Damage
  # event, action=repair, rc=0 — durable proof the tower SAW the
  # CLI-inflicted damage and REPAIRED it. Same transient trap as the
  # invader: tower repair is 800/tick at close range, the 999 missing
  # hits vanish in one tick, so stats.damaged is a one-tick blip that
  # a seconds-granularity poll cannot be required to catch. The flight
  # recorder latches it instead.
  pollTowerRepairSeen = writeShellScript "poll-tower-repair-seen" ''
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
    T=$(decode trace)
    if [ "$T" = absent ]; then echo "no trace in memory yet"; exit 1; fi
    echo "tower trace: $(printf '%s' "$T" | ${jq}/bin/jq -c \
      '[.[] | .[] | select(.event | startswith("hostile") or startswith("calm"))]') \
(damaged now: $(decode stats.damaged))"
    printf '%s' "$T" | ${jq}/bin/jq -e '
      [.[] | .[] | select((.event | endswith("Damage"))
                          and .action == "repair" and .rc == 0)]
      | length > 0
    ' > /dev/null
  '';

  # One-shot probe: stats.damaged == 0 AFTER pollTowerRepairSeen
  # latched the repair — no damaged structure remains (calm+Damage ->
  # repairing per the spec's attack>repair priority). If the shell had
  # never seen the damage at all, the repair would not fire and this
  # would sit at damaged >= 1 forever — the pair of probes closes both
  # failure modes.
  pollRepaired = writeShellScript "poll-repaired" ''
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
    D=$(decode stats.damaged)
    echo "damaged: $D (towers: $(decode stats.towers))"
    [ "$D" != absent ] && [ "$D" -eq 0 ]
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
  # 5700s, plus the tutorial-5 defense arc (RCL surgery 60s + 300s,
  # tower build 2500s + feed 300s, invader 60s + 120s + 300s + 300s,
  # repair 60s + 120s + 300s, heartbeat 300s ≈ 4720s) ≈ 10400s of
  # deadlines, plus boot and deploy — far past the driver's default
  # 3600s global timeout.
  globalTimeout = 14400;

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

    with subtest("controller forced to RCL 3 (world surgery)"):
        # Towers unlock at RCL 3; grinding there honestly would dwarf
        # every other deadline, so the server CLI raises the itest
        # room's controller directly. The surgery script discovers the
        # room from the itest user's spawn in the same REPL session —
        # a short retry loop covers CLI connection flakiness.
        deadline = time.time() + 60
        while True:
            status, out = machine.execute("${surgeryRcl3} 2>&1")
            print(f">>> rcl3 surgery: {out.strip()}")
            if status == 0:
                print(">>> RCL3 surgery acknowledged")
                break
            if time.time() > deadline:
                raise Exception("RCL3 world surgery was never acknowledged by the CLI")
            time.sleep(5)
        deadline = time.time() + 300
        while True:
            status, out = machine.execute("${pollControllerLevel3} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: shell observes controller at RCL 3")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for controllerLevel >= 3 after surgery")
            time.sleep(2)

    with subtest("tower gets built and fed"):
        # Tutorial-5 build proof: at RCL 3 the shell places the
        # spec-driven tower site (towerOffsets) and the builders haul
        # 5000 build-energy into it — the extension's 3000 had a 1500s
        # deadline, so 5000 gets 2500s. Then the harvesters feed the
        # below-target tower (an energy sink while energy <
        # towerEnergyTarget = 500): energy > 0 within 300s.
        deadline = time.time() + 2500
        while True:
            status, out = machine.execute("${pollTowerBuilt} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower built")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the tower to be built")
            time.sleep(2)
        deadline = time.time() + 300
        while True:
            status, out = machine.execute("${pollTowerFed} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower fed (energy > 0)")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the tower to receive energy")
            time.sleep(2)

    with subtest("invader dies to the tower"):
        # Insert a 2-part hostile creep owned by the Invader NPC user
        # near the spawn, then require: the tower ENGAGED it —
        # Memory.trace holds hostile*/attack/rc=0 (durable; the
        # sighting and the 600-vs-200 one-shot kill share a single
        # tick, so transient stats can never be required) — and the
        # threat CLEARED (stats.hostiles == 0). Afterward the colony
        # must still stand at desired strength.
        deadline = time.time() + 60
        while True:
            status, out = machine.execute("${surgeryInsertInvader} 2>&1")
            print(f">>> invader surgery: {out.strip()}")
            if status == 0:
                print(">>> invader inserted")
                break
            if time.time() > deadline:
                raise Exception("invader insertion was never acknowledged by the CLI")
            time.sleep(5)
        deadline = time.time() + 120
        while True:
            status, out = machine.execute("${pollTowerEngaged} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower saw the invader and fired (trace latched)")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for a tower attack in Memory.trace")
            time.sleep(2)
        deadline = time.time() + 300
        while True:
            status, out = machine.execute("${pollInvaderDead} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: invader dead — tower defense works")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the tower to kill the invader")
            time.sleep(2)
        deadline = time.time() + 300
        while True:
            status, out = machine.execute("${pollColonyIntact} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: colony still at strength after the fight")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for role counts after the invader fight")
            time.sleep(2)

    with subtest("tower repairs battle damage (world surgery)"):
        # CLI-damage the extension (hits -> 1), then require the tower
        # to have SEEN and REPAIRED it — Memory.trace holds
        # *Damage/repair/rc=0 (durable; 800 repair/tick up close heals
        # the 999 missing hits in one tick, another one-tick transient)
        # — and stats.damaged back to 0 (nothing left broken).
        deadline = time.time() + 60
        while True:
            status, out = machine.execute("${surgeryDamageExtension} 2>&1")
            print(f">>> damage surgery: {out.strip()}")
            if status == 0:
                print(">>> extension damaged")
                break
            if time.time() > deadline:
                raise Exception("extension damage was never acknowledged by the CLI")
            time.sleep(5)
        deadline = time.time() + 120
        while True:
            status, out = machine.execute("${pollTowerRepairSeen} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower saw the damage and repaired (trace latched)")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for a tower repair in Memory.trace")
            time.sleep(2)
        deadline = time.time() + 300
        while True:
            status, out = machine.execute("${pollRepaired} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: tower repaired the extension")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for the tower repair")
            time.sleep(2)

    with subtest("economy heartbeat unbroken"):
        # Fresh baseline AFTER all the surgery (the RCL3 surgery zeroed
        # controller progress, so any earlier baseline is meaningless),
        # then progress strictly above it — the whole defense arc left
        # the upgrader pipeline beating.
        heartbeat_baseline = int(machine.succeed("${readControllerProgress}").strip())
        print(f">>> controller progress after the defense arc: {heartbeat_baseline}")
        deadline = time.time() + 300
        while True:
            status, out = machine.execute(f"${pollProgressAfterDeath} {heartbeat_baseline} 2>&1")
            print(f">>> poll: {out.strip()}")
            if status == 0:
                print(">>> SUCCESS: controller progress rose after the defense arc")
                break
            if time.time() > deadline:
                print(">>> TIMEOUT — server log tail for diagnosis:")
                print(machine.succeed("journalctl -u screeps --no-pager | tail -n 100"))
                raise Exception("timed out waiting for post-defense controller progress")
            time.sleep(2)
  '';
}
