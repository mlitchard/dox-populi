// Wrapper around @screeps/renderer: metadata compilation, world
// configuration, and the room camera (wheel zoom, drag pan). Config
// values come from the renderer repo's demo (docs/viewer-contract.md).

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

const MAX_ZOOM_IN = 20;

export interface RoomView {
  applyState(state: Record<string, unknown>, tickSeconds: number): void;
  // Screen pixels → room tile under the current pan and zoom.
  tileAt(px: number, py: number): { x: number; y: number } | undefined;
  // Screen-pixel square of a tile, for the hover highlight.
  tileRect(tile: { x: number; y: number }): {
    left: number;
    top: number;
    size: number;
  };
  // Resize the canvas to a new square side, keeping the framing.
  setSize(side: number): void;
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

  let side = Math.min(container.clientWidth, container.clientHeight);
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

  // zoomLevel is the stage scale: screen pixels per world pixel
  // (engine/src/lib/GameRenderer.js). The fit value shows the whole
  // room; the stage stays at the origin until the user pans.
  const stage = renderer.app.stage;
  const fitZoom = (): number => side / WORLD_SIZE;
  renderer.zoomLevel = fitZoom();

  // Keep the zoom between whole-room and MAX_ZOOM_IN×, and keep the
  // room covering the canvas so no empty space scrolls into view.
  const clampView = (): void => {
    const zoom = Math.min(
      fitZoom() * MAX_ZOOM_IN,
      Math.max(fitZoom(), stage.scale.x),
    );
    if (zoom !== stage.scale.x) renderer.zoomLevel = zoom;
    const extent = WORLD_SIZE * zoom;
    for (const axis of ["x", "y"] as const) {
      const min = Math.min(0, side - extent);
      stage.position[axis] = Math.max(min, Math.min(0, stage.position[axis]));
    }
  };

  container.addEventListener(
    "wheel",
    (ev) => {
      ev.preventDefault();
      const rect = container.getBoundingClientRect();
      const factor = ev.deltaY < 0 ? 1.15 : 1 / 1.15;
      renderer.zoomTo(
        stage.scale.x * factor,
        ev.clientX - rect.left,
        ev.clientY - rect.top,
      );
      clampView();
    },
    { passive: false },
  );

  // Drag pans; a drag also fires a click on release, which this
  // swallows before the placement and inspector handlers (registered
  // later, so they run after this one).
  let dragging = false;
  let dragMoved = false;
  let startX = 0;
  let startY = 0;
  let lastX = 0;
  let lastY = 0;
  container.addEventListener("pointerdown", (ev) => {
    if (ev.button !== 0) return;
    dragging = true;
    dragMoved = false;
    startX = lastX = ev.clientX;
    startY = lastY = ev.clientY;
    container.setPointerCapture(ev.pointerId);
  });
  container.addEventListener("pointermove", (ev) => {
    if (!dragging) return;
    if (!dragMoved && Math.hypot(ev.clientX - startX, ev.clientY - startY) > 4) {
      dragMoved = true;
    }
    if (dragMoved) {
      renderer.pan(ev.clientX - lastX, ev.clientY - lastY);
      clampView();
    }
    lastX = ev.clientX;
    lastY = ev.clientY;
  });
  const endDrag = (): void => {
    dragging = false;
  };
  container.addEventListener("pointerup", endDrag);
  container.addEventListener("pointercancel", endDrag);
  container.addEventListener("click", (ev) => {
    if (dragMoved) {
      ev.stopImmediatePropagation();
      dragMoved = false;
    }
  });

  return {
    applyState: (state, tickSeconds) => renderer.applyState(state, tickSeconds),
    tileAt(px, py) {
      const x = Math.floor((px - stage.position.x) / stage.scale.x / CELL_SIZE);
      const y = Math.floor((py - stage.position.y) / stage.scale.y / CELL_SIZE);
      if (x < 0 || y < 0 || x >= ROOM_TILES || y >= ROOM_TILES) return undefined;
      return { x, y };
    },
    tileRect(tile) {
      const size = stage.scale.x * CELL_SIZE;
      return {
        left: stage.position.x + tile.x * size,
        top: stage.position.y + tile.y * size,
        size,
      };
    },
    setSize(newSide) {
      if (!newSide || Math.abs(newSide - side) < 1) return;
      const factor = newSide / side;
      renderer.resize({ width: newSide, height: newSide });
      renderer.zoomLevel = stage.scale.x * factor;
      stage.position.x *= factor;
      stage.position.y *= factor;
      side = newSide;
      clampView();
    },
    release: () => renderer.release(),
  };
}
