// Mouse layer: hover highlight and click-to-inspect. Picking runs
// against our own object map on the 50x50 tile grid, independent of
// renderer internals.

import type { RoomState } from "./state";
import type { RoomView } from "./render";
import type { Api, RoomObject } from "./protocol";

// Progress required to reach the next controller level, copied from
// @screeps/common lib/constants.js. The server sends a controller's
// progress with no total.
const CONTROLLER_LEVELS: Record<number, number> = {
  1: 200,
  2: 45000,
  3: 135000,
  4: 405000,
  5: 1215000,
  6: 3645000,
  7: 10935000,
};

function fieldRows(obj: RoomObject, state: RoomState): string[] {
  const rows: string[] = [];
  const consumed = new Set(["_id", "type", "room", "x", "y", "meta", "$loki"]);
  const owner = typeof obj.user === "string" ? state.users[obj.user] : undefined;
  if (typeof obj.name === "string") {
    rows.push(`name: ${obj.name}`);
    consumed.add("name");
  }
  if (owner) {
    rows.push(`owner: ${owner.username}`);
    consumed.add("user");
  }
  if (typeof obj.hits === "number") {
    rows.push(`hits: ${obj.hits} / ${obj.hitsMax ?? "?"}`);
    consumed.add("hits").add("hitsMax");
  }
  if (typeof obj.energy === "number") {
    rows.push(`energy: ${obj.energy}${obj.energyCapacity ? ` / ${obj.energyCapacity}` : ""}`);
    consumed.add("energy").add("energyCapacity");
  }
  const store = obj.store;
  if (store && typeof store === "object") {
    for (const [res, amount] of Object.entries(store as Record<string, unknown>)) {
      if (typeof amount === "number" && amount > 0) rows.push(`store.${res}: ${amount}`);
    }
    consumed.add("store");
  }
  if (Array.isArray(obj.body)) {
    const counts: Record<string, number> = {};
    for (const part of obj.body as Array<{ type?: string }>) {
      if (part?.type) counts[part.type] = (counts[part.type] ?? 0) + 1;
    }
    rows.push(`body: ${Object.entries(counts).map(([t, n]) => `${n}×${t}`).join(", ")}`);
    consumed.add("body");
  }
  if (typeof obj.level === "number") {
    rows.push(`level: ${obj.level}`);
    consumed.add("level");
  }
  if (typeof obj.progress === "number") {
    const total =
      typeof obj.progressTotal === "number"
        ? obj.progressTotal
        : obj.type === "controller" && typeof obj.level === "number"
          ? CONTROLLER_LEVELS[obj.level]
          : undefined;
    rows.push(`progress: ${obj.progress}${total ? ` / ${total}` : ""}`);
    consumed.add("progress").add("progressTotal");
  }
  if (typeof obj.ageTime === "number") {
    rows.push(`ticks to live: ${obj.ageTime - state.gameTime}`);
    consumed.add("ageTime");
  }
  if (typeof obj.nextRegenerationTime === "number") {
    rows.push(`ticks to regeneration: ${obj.nextRegenerationTime - state.gameTime}`);
    consumed.add("nextRegenerationTime");
  }
  if (typeof obj.downgradeTime === "number") {
    rows.push(`ticks to downgrade: ${obj.downgradeTime - state.gameTime}`);
    consumed.add("downgradeTime");
  }
  const actionLog = obj.actionLog;
  if (actionLog && typeof actionLog === "object") {
    for (const [action, v] of Object.entries(actionLog as Record<string, unknown>)) {
      const detail = v as { x?: number; y?: number; message?: string } | null;
      let value: string;
      if (detail === null) {
        value = "null";
      } else if (typeof detail.message === "string") {
        value = `"${detail.message}"`;
      } else if (typeof detail.x === "number" && typeof detail.y === "number") {
        value = `@ ${detail.x},${detail.y}`;
      } else {
        value = JSON.stringify(detail);
      }
      rows.push(`actionLog.${action}: ${value}`);
    }
    consumed.add("actionLog");
  }
  if (typeof obj.safeMode === "number") {
    if (obj.safeMode > state.gameTime) {
      rows.push(`safe mode: ${obj.safeMode - state.gameTime} ticks left`);
    }
    consumed.add("safeMode");
  }
  for (const [key, value] of Object.entries(obj)) {
    if (consumed.has(key) || value === undefined) continue;
    if (value !== null && typeof value === "object") {
      rows.push(`${key}: ${JSON.stringify(value)}`);
    } else {
      rows.push(`${key}: ${String(value)}`);
    }
  }
  return rows;
}

export class Inspector {
  private selected?: { x: number; y: number };
  private memory?: { name: string; value: unknown };
  private memoryPending = false;

  constructor(
    private readonly container: HTMLElement,
    private readonly highlight: HTMLElement,
    private readonly panel: HTMLElement,
    public view: RoomView,
    private readonly state: RoomState,
    private readonly api: Api,
  ) {
    container.addEventListener("mousemove", (ev) => {
      const tile = this.tileFromEvent(ev);
      if (tile) this.moveHighlight(tile);
      else this.highlight.style.display = "none";
    });
    container.addEventListener("mouseleave", () => {
      this.highlight.style.display = "none";
    });
    container.addEventListener("click", (ev) => {
      this.selected = this.tileFromEvent(ev);
      this.renderPanel();
    });
  }

  private tileFromEvent(ev: MouseEvent): { x: number; y: number } | undefined {
    const rect = this.container.getBoundingClientRect();
    return this.view.tileAt(ev.clientX - rect.left, ev.clientY - rect.top);
  }

  private moveHighlight(tile: { x: number; y: number }): void {
    const rect = this.view.tileRect(tile);
    this.highlight.style.display = "block";
    this.highlight.style.width = `${rect.size}px`;
    this.highlight.style.height = `${rect.size}px`;
    this.highlight.style.left = `${rect.left}px`;
    this.highlight.style.top = `${rect.top}px`;
  }

  // One request at a time; each response redraws, and the next tick's
  // renderPanel starts the next request.
  private fetchMemory(name: string): void {
    if (this.memoryPending) return;
    this.memoryPending = true;
    this.api.memory(`creeps.${name}`).then(
      (value) => {
        this.memoryPending = false;
        this.memory = { name, value };
        this.draw();
      },
      () => {
        this.memoryPending = false;
      },
    );
  }

  // Re-render the panel each tick so the selected tile shows live data.
  renderPanel(): void {
    if (!this.selected) return;
    const creep = this.state
      .objectsAt(this.selected.x, this.selected.y)
      .find((o) => o.type === "creep" && typeof o.name === "string");
    if (creep) this.fetchMemory(creep.name as string);
    this.draw();
  }

  private draw(): void {
    if (!this.selected) return;
    const { x, y } = this.selected;
    const objects = this.state.objectsAt(x, y);
    const parts: string[] = [`<h2>tile ${x},${y}</h2>`];
    if (objects.length === 0) {
      parts.push("<p>nothing here</p>");
    }
    for (const obj of objects) {
      parts.push(`<h3>${obj.type} · ${obj._id}</h3>`);
      parts.push("<ul>");
      for (const row of fieldRows(obj, this.state)) {
        parts.push(`<li>${row}</li>`);
      }
      parts.push("</ul>");
      if (obj.type === "creep" && this.memory && this.memory.name === obj.name) {
        parts.push(`<h3>memory</h3>`);
        parts.push(`<pre>${JSON.stringify(this.memory.value, null, 1)}</pre>`);
      }
    }
    this.panel.innerHTML = parts.join("");
  }
}
