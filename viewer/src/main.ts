// Shell: connect form → REST seed → renderer → socket feed → panel.

import { Api } from "./protocol";
import { RoomState } from "./state";
import { Feed } from "./feed";
import { createRoomView } from "./render";
import { Inspector } from "./inspect";

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
  const rooms = await api.rooms(me._id);
  const room = rooms[0] ?? (await api.worldStartRoom());
  if (!room) throw new Error("no room found for this account — run deploy-local first");

  status.textContent = `loading ${room}…`;
  const terrain = await api.terrain(room);
  const seed = await api.roomObjects(room);

  const state = new RoomState();
  state.seed(seed.objects, seed.users);
  state.addUser({ _id: me._id, username: me.username });

  el<HTMLElement>("connect").style.display = "none";
  el<HTMLElement>("viewer").style.display = "flex";
  el<HTMLElement>("roomname").textContent = room;

  const container = el<HTMLElement>("room");
  const view = await createRoomView(container, {
    apiBase: api.base,
    playerId: me._id,
    terrain,
  });
  const inspector = new Inspector(
    container,
    el<HTMLElement>("highlight"),
    el<HTMLElement>("panel"),
    view,
    state,
  );

  view.applyState(state.toRenderState(), 0);

  let lastTickAt = 0;
  let tickSeconds = 1;
  const feed = new Feed(api.wsUrl, {
    onTokenRotated: (token) => api.adoptToken(token),
    onChannel: (channel, payload, first) => {
      if (!channel.startsWith("room:")) return;
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
      status.textContent = "connection lost — reload to reconnect";
      el<HTMLElement>("connect").style.display = "block";
    },
  });
  await feed.connect(api.currentToken);
  feed.subscribe(`room:${room}`);
  status.textContent = "";
}

const form = el<HTMLFormElement>("connect-form");
form.addEventListener("submit", (ev) => {
  ev.preventDefault();
  const server = el<HTMLInputElement>("server").value;
  const email = el<HTMLInputElement>("email").value;
  const password = el<HTMLInputElement>("password").value;
  start(server, email, password).catch((err: Error) => {
    el<HTMLElement>("status").textContent = err.message;
  });
});

el<HTMLInputElement>("server").value = `http://${location.hostname}:21025`;
