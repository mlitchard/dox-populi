// REST client for the private server. One mutable token cell: every
// request sends the current token as both X-Token and X-Username, and
// every response may rotate it via the X-Token response header
// (docs/viewer-contract.md).

export interface UserInfo {
  _id: string;
  username: string;
  badge?: unknown;
}

export interface RoomObject {
  _id: string;
  type: string;
  room: string;
  x: number;
  y: number;
  [key: string]: unknown;
}

export type TerrainTile = { x: number; y: number; type: "wall" | "swamp" };

export class Api {
  private token = "";

  constructor(public readonly base: string) {}

  get wsUrl(): string {
    return this.base.replace(/^http/, "ws") + "/socket/websocket";
  }

  get currentToken(): string {
    return this.token;
  }

  adoptToken(token: string): void {
    this.token = token;
  }

  private async req<T>(path: string, init?: RequestInit): Promise<T> {
    const headers = new Headers(init?.headers);
    headers.set("Content-Type", "application/json");
    if (this.token) {
      headers.set("X-Token", this.token);
      headers.set("X-Username", this.token);
    }
    const res = await fetch(`${this.base}${path}`, { ...init, headers });
    const rotated = res.headers.get("x-token");
    if (rotated) this.token = rotated;
    if (!res.ok) {
      throw new Error(`${path}: HTTP ${res.status} ${await res.text()}`);
    }
    return (await res.json()) as T;
  }

  async signin(email: string, password: string): Promise<void> {
    const body = JSON.stringify({ email, password });
    const res = await this.req<{ ok: number; token: string }>(
      "/api/auth/signin",
      { method: "POST", body },
    );
    this.token = res.token;
  }

  me(): Promise<UserInfo> {
    return this.req<UserInfo>("/api/auth/me");
  }

  async rooms(userId: string): Promise<string[]> {
    // Private servers answer with a flat `rooms` or `list` array and
    // no `shards` key.
    const res = await this.req<{
      rooms?: string[];
      list?: string[];
      shards?: Record<string, string[]>;
    }>(`/api/user/rooms?id=${encodeURIComponent(userId)}`);
    if (res.rooms?.length) return res.rooms;
    if (res.list?.length) return res.list;
    if (res.shards) return Object.values(res.shards).flat();
    return [];
  }

  async worldStartRoom(): Promise<string | undefined> {
    const res = await this.req<{ room: string[] }>("/api/user/world-start-room");
    return res.room?.[0];
  }

  async terrain(room: string): Promise<TerrainTile[]> {
    const res = await this.req<{
      terrain: Array<Record<string, unknown>>;
    }>(`/api/game/room-terrain?room=${encodeURIComponent(room)}`);
    const first = res.terrain?.[0];
    // Rare private-server worlds answer with the encoded form (a 2500
    // digit string) regardless of the query — sniff and expand.
    if (first && typeof first.terrain === "string") {
      const s = first.terrain as string;
      const tiles: TerrainTile[] = [];
      for (let i = 0; i < s.length; i += 1) {
        const c = s[i];
        if (c === "0") continue;
        tiles.push({
          x: i % 50,
          y: Math.floor(i / 50),
          type: c === "2" ? "swamp" : "wall",
        });
      }
      return tiles;
    }
    return (res.terrain ?? []) as TerrainTile[];
  }

  async roomObjects(
    room: string,
  ): Promise<{ objects: RoomObject[]; users: Record<string, UserInfo> }> {
    const res = await this.req<{
      objects: RoomObject[];
      users: Record<string, UserInfo>;
    }>(`/api/game/room-objects?room=${encodeURIComponent(room)}`);
    return { objects: res.objects ?? [], users: res.users ?? {} };
  }

  async findUser(id: string): Promise<UserInfo | undefined> {
    const res = await this.req<{ user?: UserInfo }>(
      `/api/user/find?id=${encodeURIComponent(id)}`,
    );
    return res.user;
  }
}
