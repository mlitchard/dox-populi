// A server mod, wired into the private server by flake.nix. It runs
// inside the server process against the database, on a timer. It
// replaces the engine's built-in invader generation (genInvaders)
// with genRaiders, which inserts raider creeps for the "raiders"
// user under the rules of the spec's raidPolicy.
import { raidBody, raidPolicy } from "../generated/invader";

// The NPC user that owns all raider creeps. Must match the _id of the
// user seeded by flake.nix.
const RAIDER_USER = "raiders";

// The database collection methods used in this file. The server
// provides the real collections untyped; this typing covers only what
// is called here.
interface DbCollection {
  find(query: object): Promise<Record<string, any>[]>;
  findOne(query: object): Promise<Record<string, any> | null>;
  insert(doc: object): Promise<unknown>;
  update(query: object, update: object): Promise<unknown>;
}

// The parts of the config object the server passes to raidMod at
// startup: the cronjob table and the storage handles.
interface ServerConfig {
  cronjobs?: Record<string, unknown[]>;
  common?: {
    storage?: {
      db?: Record<string, DbCollection>;
      env?: { get(key: string): Promise<string | null> };
    };
  };
}

// Collects the walkable squares on the room's border, where raiders
// enter. The terrain string holds one digit per tile of the 50x50
// room, row-major; an odd digit is a wall.
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

// Builds the database document for one raider creep, copying the
// shape the engine gives its own creep documents. The body parts come
// from the spec's raidBody.
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

// Decides, for each owned room, whether a raid starts now, and inserts
// the wave when it does. A raid waits until the room has
// raidPolicy.minTowers fully loaded towers and enough energy has been
// harvested to reach the goal; a goal of 1 skips both checks so a raid
// can be forced. Each wave is sizeStep raiders larger than the last.
async function genRaiders(
  db: Record<string, DbCollection>,
  env: { get(key: string): Promise<string | null> }
): Promise<void> {
  const gameTime = parseInt((await env.get("gameTime")) ?? "0", 10) || 0;
  const controllers = await db["rooms.objects"].find({ type: "controller" });
  for (const controller of controllers) {
    if (!controller.user || controller.user === RAIDER_USER) continue;
    if (typeof controller.safeMode === "number" && controller.safeMode > gameTime)
      continue;
    const room: string = controller.room;
    const roomDoc = await db["rooms"].findOne({ _id: room });
    const goal: number = (roomDoc && roomDoc.invaderGoal) || raidPolicy.goal;
    if (goal !== 1) {
      // A tower counts as fully loaded when its energy reaches
      // towerFullEnergy, which must stay equal to creeps.dox's
      // towerRefillTarget: a full tower.
      const towers = await db["rooms.objects"].find({ room, type: "tower" });
      const loaded = towers.filter(
        (t) => ((t.store && t.store.energy) || 0) >= raidPolicy.towerFullEnergy
      );
      if (loaded.length < raidPolicy.minTowers) continue;
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
    // deploy-local (flake.nix) resets raidWave to 0, so escalation
    // starts over on every fresh deploy.
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

// The server runs several processes and loads this file into all of
// them; only the process with a cronjob table performs the swap.
// Storage connects after this function runs, so the timer's callback
// looks up the db handles at each firing.
const raidMod = (config: ServerConfig): void => {
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
