// Mouse layer: hover highlight and click-to-inspect. Picking runs
// against our own object map on the 50x50 tile grid, independent of
// renderer internals.

import type { RoomState } from "./state";
import type { RoomView } from "./render";
import type { RoomObject } from "./protocol";

const CELL_SIZE = 100;

function fieldRows(obj: RoomObject, state: RoomState): string[] {
  const rows: string[] = [];
  const owner = typeof obj.user === "string" ? state.users[obj.user] : undefined;
  if (typeof obj.name === "string") rows.push(`name: ${obj.name}`);
  if (owner) rows.push(`owner: ${owner.username}`);
  if (typeof obj.hits === "number") rows.push(`hits: ${obj.hits} / ${obj.hitsMax ?? "?"}`);
  if (typeof obj.energy === "number") {
    rows.push(`energy: ${obj.energy}${obj.energyCapacity ? ` / ${obj.energyCapacity}` : ""}`);
  }
  const store = obj.store;
  if (store && typeof store === "object") {
    for (const [res, amount] of Object.entries(store as Record<string, unknown>)) {
      if (typeof amount === "number" && amount > 0) rows.push(`store.${res}: ${amount}`);
    }
  }
  if (Array.isArray(obj.body)) {
    const counts: Record<string, number> = {};
    for (const part of obj.body as Array<{ type?: string }>) {
      if (part?.type) counts[part.type] = (counts[part.type] ?? 0) + 1;
    }
    rows.push(`body: ${Object.entries(counts).map(([t, n]) => `${n}×${t}`).join(", ")}`);
  }
  if (typeof obj.level === "number") rows.push(`level: ${obj.level}`);
  if (typeof obj.progress === "number") {
    rows.push(`progress: ${obj.progress}${obj.progressTotal ? ` / ${obj.progressTotal}` : ""}`);
  }
  return rows;
}

export class Inspector {
  private selected?: { x: number; y: number };

  constructor(
    private readonly container: HTMLElement,
    private readonly highlight: HTMLElement,
    private readonly panel: HTMLElement,
    public view: RoomView,
    private readonly state: RoomState,
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
    const px = this.view.scale * CELL_SIZE;
    this.highlight.style.display = "block";
    this.highlight.style.width = `${px}px`;
    this.highlight.style.height = `${px}px`;
    this.highlight.style.left = `${tile.x * px}px`;
    this.highlight.style.top = `${tile.y * px}px`;
  }

  // Re-render the panel each tick so the selected tile shows live data.
  renderPanel(): void {
    if (!this.selected) return;
    const { x, y } = this.selected;
    const objects = this.state.objectsAt(x, y);
    const parts: string[] = [`<h2>tile ${x},${y}</h2>`];
    if (objects.length === 0) {
      parts.push("<p>nothing here</p>");
    }
    for (const obj of objects) {
      parts.push(`<h3>${obj.type}</h3>`);
      parts.push("<ul>");
      for (const row of fieldRows(obj, this.state)) {
        parts.push(`<li>${row}</li>`);
      }
      parts.push("</ul>");
    }
    this.panel.innerHTML = parts.join("");
  }
}
