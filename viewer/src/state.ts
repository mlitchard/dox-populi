// Accumulated room state. The socket sends one full snapshot per
// subscription and diffs after that; the renderer wants a complete
// object array every tick — this module bridges the two
// (docs/viewer-contract.md).

import type { RoomObject, UserInfo } from "./protocol";

function isPlainObject(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

// A diff value landing on an array field (creep body) arrives as an
// index-keyed object; merge it element-wise. Everything else: null
// deletes the field, nested objects merge, scalars and arrays replace.
function mergeInto(target: Record<string, unknown>, diff: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(diff)) {
    if (value === null) {
      delete target[key];
    } else if (isPlainObject(value) && Array.isArray(target[key])) {
      const arr = target[key] as unknown[];
      for (const [idx, elem] of Object.entries(value)) {
        const i = Number(idx);
        if (isPlainObject(elem) && isPlainObject(arr[i])) {
          mergeInto(arr[i] as Record<string, unknown>, elem);
        } else {
          arr[i] = elem;
        }
      }
    } else if (isPlainObject(value) && isPlainObject(target[key])) {
      mergeInto(target[key] as Record<string, unknown>, value);
    } else {
      target[key] = value;
    }
  }
}

export class RoomState {
  readonly objects = new Map<string, RoomObject>();
  readonly users: Record<string, UserInfo> = {};
  gameTime = 0;

  seed(objects: RoomObject[], users: Record<string, UserInfo>): void {
    this.objects.clear();
    for (const obj of objects) this.objects.set(obj._id, structuredClone(obj));
    Object.assign(this.users, users);
  }

  // The socket's first message per subscription is a full snapshot;
  // later ones are diffs (id → changed fields, id → null for removal).
  apply(payload: {
    objects: Record<string, Record<string, unknown> | null>;
    gameTime?: number;
  }, snapshot: boolean): void {
    if (typeof payload.gameTime === "number") this.gameTime = payload.gameTime;
    if (snapshot) this.objects.clear();
    for (const [id, diff] of Object.entries(payload.objects ?? {})) {
      if (diff === null) {
        this.objects.delete(id);
      } else if (this.objects.has(id)) {
        mergeInto(this.objects.get(id) as unknown as Record<string, unknown>, diff);
      } else {
        const obj = structuredClone(diff) as unknown as RoomObject;
        obj._id = id;
        this.objects.set(id, obj);
      }
    }
  }

  addUser(user: UserInfo): void {
    this.users[user._id] = user;
  }

  // User ids referenced by objects but absent from the users map —
  // the room feed carries no users, so these get fetched.
  missingUserIds(): string[] {
    const missing = new Set<string>();
    for (const obj of this.objects.values()) {
      const user = obj.user;
      if (typeof user === "string" && !this.users[user]) missing.add(user);
    }
    return [...missing];
  }

  objectsAt(x: number, y: number): RoomObject[] {
    const found: RoomObject[] = [];
    for (const obj of this.objects.values()) {
      if (obj.x === x && obj.y === y) found.push(obj);
    }
    return found;
  }

  toRenderState(): Record<string, unknown> {
    return {
      objects: [...this.objects.values()].map((o) => structuredClone(o)),
      users: this.users,
      gameTime: this.gameTime,
      info: { mode: "world" },
      visual: "",
    };
  }
}
