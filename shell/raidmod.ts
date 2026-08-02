// dox-populi raid mod: the world's raid LAW. Loaded from mods.json into
// the backend process, where it REPLACES the engine's native genInvaders
// cron (which inserts uid-2 creeps driven by hardcoded engine AI — the
// enemy this project outlawed) with raids of "raiders"-owned creeps, so
// every raider that ever walks this world is driven by the Paradox brain
// (dox/invader → generated/invader.ts → shell/invader.ts users.code).
//
// This file is HANDS. Every policy number — the harvested-energy goal,
// the raid size, the cron cadence, the body — is spec data imported from
// generated/invader.ts. The mod only observes the db and inserts
// documents. Native-parity semantics preserved mechanically (upstream
// backend-local/lib/cronjobs.js genInvaders):
//   - the engine itself maintains source.invaderHarvested on every
//     harvest (engine/src/processor/intents/creeps/harvest.js); the mod
//     just sums it
//   - per-room override: room.invaderGoal || raidPolicy.goal, and
//     invaderGoal == 1 means "raid NOW" (director's dial; the itest's
//     sterilizer is a huge value)
// Deliberate differences from native: no raid while the controller's
// safeMode runs (the engine refuses hostile creep actions there — the
// ERR_NO_BODYPART masquerade; a raid into it is theater, not war);
// exit-square choice is DETERMINISTIC (fixed edge scan, first squares) —
// reproducible aggression is the raider contract, mod included; and
// RELENTLESS WAR (spec raid-law, user ruling 2026-08-01): the harvested
// counter is NEVER reset and live raiders do NOT hold off the next wave —
// once a room crosses the goal, an escalating wave lands on every cron
// check until the colony falls or the controller stops being owned. The
// durability test of a single tower, by law.
//
// Load order (verified upstream, backend-local/lib/index.js): the var
// block requires ./cronjobs (which assigns config.cronjobs wholesale)
// BEFORE start() calls configManager.load() (which runs mods) — so this
// mod sees the populated table and gets the last word. Only the backend
// process has config.cronjobs; everywhere else the guard exits.

import { raidBody, raidPolicy } from "../generated/invader";

// Identity plumbing, not policy: the NPC user seeded by the flake's seed
// step (users doc _id "raiders" + users.code carrying the invader
// bundle). Must match the flake jq. `active` is server-managed and gets
// normalized on boot, so it is re-armed at every insertion — same
// discipline as the itest surgery.
const RAIDER_USER = "raiders";

// ---------------------------------------------------------------------------
// Minimal structural views of the server internals the mod touches.
// ---------------------------------------------------------------------------

interface DbCollection {
  find(query: object): Promise<Record<string, any>[]>;
  findOne(query: object): Promise<Record<string, any> | null>;
  insert(doc: object): Promise<unknown>;
  update(query: object, update: object): Promise<unknown>;
}

interface ServerConfig {
  cronjobs?: Record<string, unknown[]>;
  common?: {
    storage?: {
      db?: Record<string, DbCollection>;
      env?: { get(key: string): Promise<string | null> };
    };
  };
}

// ---------------------------------------------------------------------------
// Exit squares: every open (non-wall) tile on the four room edges, in a
// FIXED scan order — top row, right column, bottom row, left column —
// with corners visited exactly once. Terrain doc is the 2500-char string;
// bit 0 is TERRAIN_MASK_WALL.
// ---------------------------------------------------------------------------

function exitSquares(terrain: string): Array<[number, number]> {
  const open = (x: number, y: number): boolean =>
    (parseInt(terrain.charAt(y * 50 + x), 10) & 1) === 0;
  const squares: Array<[number, number]> = [];
  for (let x = 0; x < 50; x++) if (open(x, 0)) squares.push([x, 0]);
  for (let y = 1; y < 49; y++) if (open(49, y)) squares.push([49, y]);
  for (let x = 0; x < 50; x++) if (open(x, 49)) squares.push([x, 49]);
  for (let y = 1; y < 49; y++) if (open(0, y)) squares.push([0, y]);
  return squares;
}

// Document shape mirrors the itest's surgery-proven raider insert (a
// REAL NPC-owned creep), plus native genInvaders' ticksToLive: 1500 so
// a raid that outlives its war dies of old age like any other creep.
function raiderDoc(
  room: string,
  square: [number, number],
  gameTime: number,
  i: number
): object {
  return {
    type: "creep",
    name: "raider-g" + gameTime + "-" + (i + 1),
    room,
    x: square[0],
    y: square[1],
    user: RAIDER_USER,
    body: raidBody.map((type) => ({ type, hits: 100 })),
    hits: raidBody.length * 100,
    hitsMax: raidBody.length * 100,
    ticksToLive: 1500,
    spawning: false,
    fatigue: 0,
    store: { energy: 0 },
    storeCapacity: 0,
    notifyWhenAttacked: false,
    actionLog: {
      attacked: null,
      healed: null,
      attack: null,
      rangedAttack: null,
      rangedMassAttack: null,
      rangedHeal: null,
      harvest: null,
      heal: null,
      repair: null,
      build: null,
      say: null,
      upgradeController: null,
      reserveController: null,
    },
  };
}

async function genRaiders(
  db: Record<string, DbCollection>,
  env: { get(key: string): Promise<string | null> }
): Promise<void> {
  const gameTime = parseInt((await env.get("gameTime")) ?? "0", 10) || 0;
  const controllers = await db["rooms.objects"].find({ type: "controller" });
  for (const controller of controllers) {
    // Only rooms somebody OWNS get raided, and never the raiders' own.
    if (!controller.user || controller.user === RAIDER_USER) continue;
    // Safe-mode deferral: safeMode is the absolute game time it expires.
    if (typeof controller.safeMode === "number" && controller.safeMode > gameTime)
      continue;
    const room: string = controller.room;
    const roomDoc = await db["rooms"].findOne({ _id: room });
    const goal: number = (roomDoc && roomDoc.invaderGoal) || raidPolicy.goal;
    if (goal !== 1) {
      // Fair-fight clause (spec: raidPolicy.minTowers + towerFullEnergy):
      // only FULLY-LOADED towers count — a room with no standing defense,
      // or a tower still loading its magazine, is not raid-eligible; a
      // colony gets built, not buried. Tower docs carry the modern store
      // shape ({store: {energy}}), same as the creeps this mod inserts.
      // The dial (goal == 1) bypasses this too: RAID NOW is a director's
      // instrument, unconditional by native parity.
      const towers = await db["rooms.objects"].find({ room, type: "tower" });
      const loaded = towers.filter(
        (t) => ((t.store && t.store.energy) || 0) >= raidPolicy.towerFullEnergy
      );
      if (loaded.length < raidPolicy.minTowers) continue;
      // Relentless war: the counter is never reset, so once harvested
      // crosses the goal this gate stays open on every check, forever.
      const sources = await db["rooms.objects"].find({ room, type: "source" });
      const harvested = sources.reduce(
        (sum, s) => sum + (s.invaderHarvested || 0),
        0
      );
      if (harvested < goal) continue;
    }
    const terrainDoc = await db["rooms.terrain"].findOne({ room });
    if (!terrainDoc) continue;
    const squares = exitSquares(terrainDoc.terrain);
    if (squares.length === 0) continue;
    // Escalation (spec: sizeStart + sizeStep * wave): room.raidWave is
    // the mod-maintained per-room raid counter — incremented after each
    // raid, cleared to 0 by deploy-local provisioning when a colony is
    // placed. The world spawns ever-increasing raids, by law.
    const wave: number = (roomDoc && roomDoc.raidWave) || 0;
    const size = raidPolicy.sizeStart + raidPolicy.sizeStep * wave;
    const chosen = squares.slice(0, size);
    await Promise.all(
      chosen.map((sq, i) =>
        db["rooms.objects"].insert(raiderDoc(room, sq, gameTime, i))
      )
    );
    await db["rooms"].update({ _id: room }, { $set: { raidWave: wave + 1 } });
    await db["users"].update(
      { _id: RAIDER_USER },
      { $set: { active: 10000 } }
    );
    console.log(
      "genRaiders: raid of " + chosen.length + " on " + room + " at t" + gameTime
    );
  }
}

const raidMod = (config: ServerConfig): void => {
  // Backend process only: that is where lib/cronjobs.js populated the
  // table. Storage is not connected yet at mod-load time — the db is
  // touched only inside the cron callback, which starts after connect.
  if (!config.cronjobs || !config.common) return;
  delete config.cronjobs["genInvaders"];
  config.cronjobs["genRaiders"] = [
    raidPolicy.checkSeconds,
    (): void => {
      const storage = config.common?.storage;
      if (!storage?.db || !storage.env) return;
      genRaiders(storage.db, storage.env).catch((e) =>
        console.error("genRaiders:", e)
      );
    },
  ];
};

export = raidMod;
