// Wrapper around @screeps/renderer: metadata compilation, world
// configuration, and the fixed whole-room camera. Config values come
// from the renderer repo's demo (docs/viewer-contract.md).

import * as rendererPkg from "@screeps/renderer";
// The metadata dist is an IIFE with no module exports: importing it
// runs a side effect that assigns window.RENDERER_METADATA.
import "@screeps/renderer-metadata";
import { resourceMap } from "./resourceMap";

// The packages ship prebuilt UMD-style bundles; where the exports land
// depends on the bundler interop. Resolve at runtime and fail with a
// named error instead of a property crash.
function resolve<T>(candidates: Array<unknown>, what: string): T {
  for (const c of candidates) {
    if (c) return c as T;
  }
  throw new Error(`could not resolve ${what} from its package exports`);
}

// Lazy: resolution failures surface on first use, inside the caller's
// error handling, instead of killing the bundle at load time.
function getGameRenderer(): GameRendererClass {
  const ns = rendererPkg as Record<string, unknown>;
  const dflt = ns.default as Record<string, unknown> | undefined;
  const umd = ns.renderer as Record<string, unknown> | undefined;
  return resolve<GameRendererClass>(
    [ns.GameRenderer, dflt?.GameRenderer, umd?.GameRenderer],
    "GameRenderer",
  );
}

function getRendererMetadata(): Record<string, unknown> {
  const meta = (globalThis as Record<string, unknown>).RENDERER_METADATA as
    | Record<string, unknown>
    | undefined;
  if (meta?.objects) return meta;
  throw new Error(
    "window.RENDERER_METADATA missing or without objects — metadata bundle not loaded",
  );
}

export const ROOM_TILES = 50;
const CELL_SIZE = 100;
export const WORLD_SIZE = ROOM_TILES * CELL_SIZE;

export interface RoomView {
  applyState(state: Record<string, unknown>, tickSeconds: number): void;
  // Screen pixels → room tile, exact because the camera is fixed to
  // show the whole room at a known scale.
  tileAt(px: number, py: number): { x: number; y: number } | undefined;
  scale: number;
  release(): void;
}

let metadataCompiled = false;

export async function createRoomView(
  container: HTMLElement,
  opts: { apiBase: string; playerId: string; terrain: Array<Record<string, unknown>> },
): Promise<RoomView> {
  console.log("renderer pkg keys:", Object.keys(rendererPkg as object));
  const GameRenderer = getGameRenderer();
  const rendererMetadata = getRendererMetadata();
  console.log(
    "resolved metadata keys:",
    Object.keys(rendererMetadata),
    "has objects:",
    rendererMetadata.objects != null,
  );
  if (!metadataCompiled) {
    console.log("compileMetadata…");
    GameRenderer.compileMetadata(rendererMetadata);
    metadataCompiled = true;
  }
  console.log("constructing GameRenderer…");

  const side = Math.min(container.clientWidth, container.clientHeight);
  const renderer = new GameRenderer({
    size: { width: side, height: side },
    resourceMap,
    useDefaultLogger: true,
    backgroundColor: 0x050505,
    worldConfigs: {
      ATTACK_PENETRATION: 10,
      CELL_SIZE,
      RENDER_SIZE: { width: 2048, height: 2048 },
      VIEW_BOX: 10000,
      ROOM_SIZE: CELL_SIZE,
      BADGE_URL: `${opts.apiBase}/api/user/badge-svg?username=%1`,
      metadata: rendererMetadata,
      lighting: "normal",
      userOwnerColor: true,
      userFlagColor: true,
      gameData: {
        player: opts.playerId,
        showMyNames: { spawns: true, creeps: true },
        showEnemyNames: { spawns: false, creeps: false },
        showFlagsNames: true,
        showCreepSpeech: false,
        swampTexture: "animated",
      },
    },
  });

  console.log("renderer.init…");
  await renderer.init(container);
  console.log("setTerrain…");
  await renderer.setTerrain(opts.terrain);
  console.log("renderer ready");

  const scale = side / WORLD_SIZE;
  renderer.zoomLevel = scale;
  renderer.cameraPosition = { x: WORLD_SIZE / 2, y: WORLD_SIZE / 2 };

  return {
    applyState: (state, tickSeconds) => renderer.applyState(state, tickSeconds),
    tileAt(px, py) {
      const x = Math.floor(px / scale / CELL_SIZE);
      const y = Math.floor(py / scale / CELL_SIZE);
      if (x < 0 || y < 0 || x >= ROOM_TILES || y >= ROOM_TILES) return undefined;
      return { x, y };
    },
    scale,
    release: () => renderer.release(),
  };
}
