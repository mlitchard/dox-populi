// Wrapper around @screeps/renderer: metadata compilation, world
// configuration, and the fixed whole-room camera. Config values come
// from the renderer repo's demo (docs/viewer-contract.md).

import rendererPkg from "@screeps/renderer";
import metadataPkg from "@screeps/renderer-metadata";
import { resourceMap } from "./resourceMap";

const { GameRenderer } = rendererPkg;

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
  if (!metadataCompiled) {
    GameRenderer.compileMetadata(metadataPkg);
    metadataCompiled = true;
  }

  const side = Math.min(container.clientWidth, container.clientHeight);
  const renderer = new GameRenderer({
    size: { width: side, height: side },
    resourceMap,
    useDefaultLogger: false,
    logger: {},
    backgroundColor: 0x050505,
    worldConfigs: {
      ATTACK_PENETRATION: 10,
      CELL_SIZE,
      RENDER_SIZE: { width: 2048, height: 2048 },
      VIEW_BOX: 10000,
      ROOM_SIZE: CELL_SIZE,
      BADGE_URL: `${opts.apiBase}/api/user/badge-svg?username=%1`,
      metadata: metadataPkg,
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

  await renderer.init(container);
  await renderer.setTerrain(opts.terrain);

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
