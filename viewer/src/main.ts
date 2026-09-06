// Shell: connect form → REST seed → renderer → socket feed → panel.

import { Api } from "./protocol";
import { RoomState } from "./state";
import { Feed } from "./feed";
import { createRoomView } from "./render";
import { Inspector } from "./inspect";
import { GameConsole } from "./console";

function el<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (!found) throw new Error(`missing element #${id}`);
  return found as T;
}

async function start(server: string, email: string, password: string): Promise<void> {
  const status = el<HTMLElement>("status");
  status.textContent = "signing in…";

  const api = new Api(server.replace(/\/+$/, ""));
  await api.signin(email, password);
  const me = await api.me();

  status.textContent = "finding room…";
  // Your own room when you have one; otherwise a room where a spawn
  // can be placed (the proxy reads controller ownership from the world
  // database), so the room on screen is always one the placement
  // click succeeds in.
  const rooms = await api.rooms(me._id);
  let room = rooms[0];
  if (!room) {
    const placeable = (await (await fetch("/placeable-rooms")).json()) as {
      rooms: string[];
    };
    room = placeable.rooms[0] ?? (await api.worldStartRoom());
  }
  if (!room) throw new Error("no room found for this account — run deploy-local first");

  status.textContent = `loading ${room}…`;
  const terrain = await api.terrain(room);

  // No REST object seed: backend 3.3.0 has no room-objects endpoint.
  // The socket's first message per subscription is a full snapshot.
  const state = new RoomState();
  state.addUser({ _id: me._id, username: me.username });

  el<HTMLElement>("connect").style.display = "none";
  el<HTMLElement>("viewer").style.display = "flex";
  el<HTMLElement>("roomname").textContent = room;

  const container = el<HTMLElement>("room");
  const viewstatus = el<HTMLElement>("viewstatus");
  const stage = (text: string): void => {
    if (viewstatus.textContent === text) return;
    console.log(`stage: ${text}`);
    viewstatus.textContent = text;
  };
  stage("starting renderer…");
  let view = await createRoomView(container, {
    apiBase: api.base,
    playerId: me._id,
    terrain,
  });
  stage("connecting socket…");
  const inspector = new Inspector(
    container,
    el<HTMLElement>("highlight"),
    el<HTMLElement>("panel"),
    view,
    state,
  );
  const gameConsole = new GameConsole(
    {
      live: el<HTMLElement>("console-live"),
      log: el<HTMLElement>("console-log"),
      form: el<HTMLFormElement>("console-form"),
      input: el<HTMLInputElement>("console-input"),
      repl: el<HTMLElement>("console-repl"),
      code: el<HTMLElement>("console-code"),
      tabLive: el<HTMLButtonElement>("tab-live"),
      tabConsole: el<HTMLButtonElement>("tab-console"),
      tabCode: el<HTMLButtonElement>("tab-code"),
    },
    api,
  );

  // The game's own onboarding: an empty world puts you in placement
  // mode — click a tile to place Spawn1; a lost colony offers respawn
  // first, which then enters the same placement mode.
  let placing = false;
  const enterPlacement = (): void => {
    placing = true;
    stage("click a tile to place Spawn1");
  };
  container.addEventListener("click", (ev) => {
    if (!placing) return;
    const rect = container.getBoundingClientRect();
    const tile = view.tileAt(ev.clientX - rect.left, ev.clientY - rect.top);
    if (!tile) return;
    void api.placeSpawn(room, tile.x, tile.y).then((result) => {
      if (result.ok) {
        placing = false;
        stage(`Spawn1 placed at ${tile.x},${tile.y}`);
      } else {
        stage(`placement refused: ${result.error ?? "unknown"} — try another tile`);
      }
    });
  });
  const respawnBtn = el<HTMLButtonElement>("respawnbtn");
  respawnBtn.style.display = "inline";
  respawnBtn.addEventListener("click", () => {
    if (!confirm("Release your colony and place a new spawn?")) return;
    console.log("respawn requested");
    api.respawn().then(
      () => {
        console.log("respawn accepted — entering placement mode");
        enterPlacement();
      },
      (err: Error) => {
        console.error(err);
        stage(`respawn failed: ${err.message}`);
      },
    );
  });
  const worldStatus = await api.worldStatus();
  if (worldStatus === "empty") {
    enterPlacement();
  } else if (worldStatus === "lost") {
    stage("colony lost — respawn to place again");
  }

  // The drag handles change the flex layout; the observer follows the
  // room cell and keeps the canvas fitted to it.
  new ResizeObserver(() => {
    view.setSize(Math.min(container.clientWidth, container.clientHeight));
  }).observe(container);

  const vsplit = el<HTMLElement>("vsplit");
  const mainRow = el<HTMLElement>("main");
  const roomWrap = el<HTMLElement>("room-wrap");
  vsplit.addEventListener("pointerdown", (ev) => {
    ev.preventDefault();
    vsplit.setPointerCapture(ev.pointerId);
    const onMove = (mv: PointerEvent): void => {
      const rect = mainRow.getBoundingClientRect();
      const pct = Math.min(85, Math.max(30, ((mv.clientX - rect.left) / rect.width) * 100));
      roomWrap.style.flexBasis = `${pct}%`;
    };
    const onUp = (): void => {
      vsplit.removeEventListener("pointermove", onMove);
      vsplit.removeEventListener("pointerup", onUp);
    };
    vsplit.addEventListener("pointermove", onMove);
    vsplit.addEventListener("pointerup", onUp);
  });

  const hsplit = el<HTMLElement>("hsplit");
  const consoleLog = el<HTMLElement>("console-log");
  const consoleLive = el<HTMLElement>("console-live");
  const consoleCode = el<HTMLElement>("console-code");
  hsplit.addEventListener("pointerdown", (ev) => {
    ev.preventDefault();
    hsplit.setPointerCapture(ev.pointerId);
    const startY = ev.clientY;
    const startH = consoleLog.getBoundingClientRect().height;
    const onMove = (mv: PointerEvent): void => {
      const h = Math.min(
        window.innerHeight * 0.6,
        Math.max(60, startH + (startY - mv.clientY)),
      );
      consoleLog.style.height = `${h}px`;
      consoleLive.style.height = `${h}px`;
      consoleCode.style.height = `${h}px`;
    };
    const onUp = (): void => {
      hsplit.removeEventListener("pointermove", onMove);
      hsplit.removeEventListener("pointerup", onUp);
    };
    hsplit.addEventListener("pointermove", onMove);
    hsplit.addEventListener("pointerup", onUp);
  });

  view.applyState(state.toRenderState(), 0);

  let lastTickAt = 0;
  let tickSeconds = 1;
  const feed = new Feed(api.wsUrl, {
    onTokenRotated: (token) => api.adoptToken(token),
    onChannel: (channel, payload, first) => {
      if (channel === `user:${me._id}/console`) {
        gameConsole.receive(payload as Parameters<GameConsole["receive"]>[0]);
        return;
      }
      if (channel !== `room:${room}`) return;
      if (!placing) stage(first ? "snapshot received" : "live");
      state.apply(payload as Parameters<RoomState["apply"]>[0], first);
      const now = performance.now();
      if (lastTickAt) tickSeconds = Math.min(5, (now - lastTickAt) / 1000);
      lastTickAt = now;
      view.applyState(state.toRenderState(), tickSeconds);
      el<HTMLElement>("gametime").textContent = String(state.gameTime || "");
      inspector.renderPanel();
      for (const id of state.missingUserIds()) {
        void api.findUser(id).then((user) => {
          if (user) state.addUser(user);
        });
      }
    },
    onClosed: () => {
      stage("connection lost — reload to reconnect");
    },
  });
  await feed.connect(api.currentToken);
  feed.subscribe(`room:${room}`);
  feed.subscribe(`user:${me._id}/console`);
  if (!placing) stage("subscribed, waiting for first snapshot…");
}

const form = el<HTMLFormElement>("connect-form");
form.addEventListener("submit", (ev) => {
  ev.preventDefault();
  const server = el<HTMLInputElement>("server").value;
  const email = el<HTMLInputElement>("email").value;
  const password = el<HTMLInputElement>("password").value;
  start(server, email, password).catch((err: Error) => {
    console.error(err);
    el<HTMLElement>("status").textContent = err.message;
    const viewstatus = document.getElementById("viewstatus");
    if (viewstatus) viewstatus.textContent = err.message;
  });
});

// Same origin as the page: the proxy forwards /api and /socket to the
// game server, so no cross-origin requests happen.
el<HTMLInputElement>("server").value = location.origin;
