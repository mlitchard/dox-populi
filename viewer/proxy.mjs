// Serves the built viewer and forwards /api and /socket to the game
// server, so the browser sees one origin and CORS never applies.
// Node builtins only; run with: node proxy.mjs
import http from "node:http";
import net from "node:net";
import { readFile } from "node:fs/promises";
import { join, normalize, extname } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));
const upstreamHost = process.env.SCREEPS_UPSTREAM_HOST || "127.0.0.1";
const upstreamPort = Number(process.env.SCREEPS_UPSTREAM_PORT || 21025);
const bind = process.env.VIEWER_HOST || "127.0.0.1";
const port = Number(process.env.VIEWER_PORT || 8080);

const types = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".mjs": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".svg": "image/svg+xml",
  ".png": "image/png",
};

const dataDir = process.env.SCREEPS_DATA_DIR || "";

// Rooms where a spawn can be placed: an unowned, unreserved controller.
// Read from the world database, the same source the server itself uses;
// no HTTP endpoint exposes controller ownership.
async function placeableRooms() {
  const db = JSON.parse(await readFile(join(dataDir, "db.json"), "utf8"));
  const objects = db.collections.find((c) => c.name === "rooms.objects");
  return (objects?.data ?? [])
    .filter(
      (o) =>
        o.type === "controller" && !(o.user ?? "") && o.reservation == null,
    )
    .map((o) => o.room);
}

const server = http.createServer((req, res) => {
  const url = req.url ?? "/";
  if (url === "/placeable-rooms") {
    placeableRooms().then(
      (rooms) => {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ rooms }));
      },
      (err) => {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ rooms: [], error: String(err) }));
      },
    );
    return;
  }
  if (url.startsWith("/api/") || url.startsWith("/socket")) {
    const proxied = http.request(
      {
        host: upstreamHost,
        port: upstreamPort,
        method: req.method,
        path: url,
        headers: { ...req.headers, host: `${upstreamHost}:${upstreamPort}` },
      },
      (up) => {
        res.writeHead(up.statusCode ?? 502, up.headers);
        up.pipe(res);
      },
    );
    proxied.on("error", () => {
      res.writeHead(502, { "Content-Type": "text/plain" });
      res.end(`upstream unavailable: ${upstreamHost}:${upstreamPort}`);
    });
    req.pipe(proxied);
    return;
  }
  let path = url.split("?")[0];
  if (path === "/") path = "/index.html";
  const file = normalize(join(root, path));
  if (!file.startsWith(root)) {
    res.writeHead(403);
    res.end();
    return;
  }
  readFile(file).then(
    (data) => {
      res.writeHead(200, {
        "Content-Type": types[extname(file)] ?? "application/octet-stream",
      });
      res.end(data);
    },
    () => {
      res.writeHead(404);
      res.end("not found");
    },
  );
});

server.on("upgrade", (req, socket, head) => {
  const up = net.connect(upstreamPort, upstreamHost, () => {
    const lines = [`${req.method} ${req.url} HTTP/1.1`];
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      lines.push(`${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}`);
    }
    up.write(lines.join("\r\n") + "\r\n\r\n");
    if (head?.length) up.write(head);
    socket.pipe(up);
    up.pipe(socket);
  });
  up.on("error", () => socket.destroy());
  socket.on("error", () => up.destroy());
});

server.listen(port, bind, () => {
  console.log(
    `viewer: http://127.0.0.1:${port}/  (proxying /api and /socket to ${upstreamHost}:${upstreamPort})`,
  );
});
