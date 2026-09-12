# dox-populi

A Screeps client whose creep population is governed by a [Paradox](https://gitlab.com/paradox_labs/paradox)
`.dox` specification: Paradox generates the typed decision logic, nix owns the
generate → typecheck → bundle pipeline, and a Screeps server runs the
result.

The server is the **open-source Screeps server, nix-vendored**, and the
viewer is an **open-source browser renderer** built from public npm
packages (`@screeps/renderer`). Building, running, and watching the world
all work without a Steam account or a purchased copy of the game. If you
do own the game, the Steam client works as an alternative viewer against
the private server.

The server runs headless on `localhost:21025`, either natively (NixOS/nix
users) or inside a self-installing dev VM (everyone else).

---

## Your encryption key

Secrets in `secrets/` are age files managed with **secrix**. Apps decrypt
them with **your** key.

- `SCREEPS_TOKEN` — screeps.com auth token, only for `nix run .#deploy`
  (the live MMO server).
- `SCREEPS_LOCAL_CREDS` — one line `username:password` for the private
  server; used by `nix run .#deploy-local`. Optional: env vars
  `SCREEPS_LOCAL_EMAIL` / `SCREEPS_LOCAL_PASSWORD` work instead.
- `STEAM_TOKEN` — a Steam Web API key, optional; only needed if you want to
  log in to the private server through Steam's native auth. Password login
  (screepsmod-auth) works without it.

Key mechanics:

- Any SSH private key works (e.g. generate one: `ssh-keygen -t ed25519`).
- Apps look for the key at, in order:
  1. `$SCREEPS_IDENTITY` (explicit override)
  2. `$WORKDIR/identity`
  3. `~/work/identity` (the conventional location — in the VM this is the
     shared host directory, see below)
- If a secret exists and no key file is found there, the app stops and tells
  you where to put it.

To (re-)encrypt a secret to your key, from the dev shell:

```sh
secrix create secrets/SCREEPS_LOCAL_CREDS -i /path/to/your/key -r "$(cat /path/to/your/key.pub)"
```

---

## Quickstart — NixOS (or any Linux with nix + flakes)

Prerequisites: nix with flakes enabled.

1. **Clone and enter the dev shell**

   ```sh
   git clone <this-repo> && cd dox-populi
   nix develop        # or `direnv allow`
   ```

   ✅ A command menu prints.

2. **Start the private server**

   ```sh
   nix run .#server
   ```

   Fully nix-built; first run downloads and builds the vendored server.
   Binds loopback by default (`SCREEPS_HOST` to change), world state in
   `.server-data/` (gitignored). Without a `STEAM_TOKEN` secret it starts
   without Steam auth — password login still works.

   ✅ `curl -s http://127.0.0.1:21025/api/version` returns JSON.

3. **Deploy**

   ```sh
   export SCREEPS_IDENTITY=/path/to/your/key   # or use the env-var creds
   nix run .#deploy-local
   ```

   Self-provisioning: creates the account, pushes `main.js` with its role modules, and auto-places `Spawn1`.

   ✅ Output ends with `auto-placed Spawn1 in <room>`.

4. **Watch it play**

   - Browser: `nix run .#client`, then open `http://127.0.0.1:8080/` and
     sign in with your deploy-local credentials. Open-source renderer —
     no purchased game files needed.
   - Or Steam client → Screeps → *Private server* → `127.0.0.1:21025`.

5. **Useful knobs**

   ```sh
   nix run .#cli           # server CLI (port 21026)
   nix run .#stop          # stop server + client, world kept
   nix run .#reset-local   # stop + wipe the world (fresh on next start)
   nix flake check         # all checks (itest and vm-boot each boot a VM)
   ```

---

## Quickstart — other Linux

Nothing is built on your machine: nix lives **inside** a dev VM that installs
itself. Host prerequisites: `qemu`, `tmux`, `curl`.

1. **Get the VM image**

   Download `dox-populi-compact.qcow2` from the project releases and place it
   next to `run-vm.sh` (or `export IMAGE_URL=<release-url>` and the script
   downloads it). Maintainers build it with `nix run .#installer`.

2. **Put your key in the shared directory**

   ```sh
   mkdir -p ~/vm-keys
   cp /path/to/your/key ~/vm-keys/identity
   ```

   `~/vm-keys` (override with `WORKDIR=`) appears inside the VM at
   `~/work`, so your key is found at its conventional path
   `~/work/identity` automatically.

3. **Boot the VM**

   ```sh
   ./run-vm.sh
   ./run-vm.sh console        # watch; Ctrl-b d detaches
   ```

   The image is a ready-to-boot dev environment; the first boot grows
   its filesystem into the virtual disk.

4. **Log in**

   ```sh
   ./run-vm.sh
   ssh -p 2222 dev@localhost             # password: dox-populi
   ```

   ✅ `ls ~/work/identity` shows your key.

   > **Note — `REMOTE HOST IDENTIFICATION HAS CHANGED!`**: every VM
   > (re)install generates fresh SSH host keys, so after a factory reset
   > your `known_hosts` still pins the old VM's key and
   > ssh refuses to connect. Not an attack — evict the stale entry and
   > retry:
   >
   > ```sh
   > ssh-keygen -R '[localhost]:2222'
   > ```

5. **Start the server and deploy** (inside the VM)

   ```sh
   cd ~/dox-populi
   nix develop        # pre-built during install — ready immediately
   nix run .#server
   ```

   The VM binds `0.0.0.0` and run-vm.sh forwards 21025/21026 to the host.

   ✅ On the **host**: `curl -s http://localhost:21025/api/version` returns
   JSON.

   Then, still in the VM: `nix run .#deploy-local`.

6. **Watch it play**

   - In the VM run `nix run .#client`, then on the host open
     `http://localhost:8080/` and sign in with your deploy-local
     credentials. Open-source renderer — no purchased game files needed.
   - Or the Steam client on the **host** → Screeps → *Private server* →
     `localhost:21025`.

### VM management

```sh
./run-vm.sh            # start (detached)
./run-vm.sh console    # serial console (Ctrl-b d = detach)
./run-vm.sh send CMD   # type a command into the console
./run-vm.sh status     # running?
./run-vm.sh kill       # stop
```

Knobs: `MEM`, `CPUS`, `DISK`, `WORKDIR`, `IMAGE_URL`. `WORKDIR`
defaults to `~/vm-keys` (skipped if it doesn't exist). Factory reset:
`rm dox-populi-compact.qcow2`.
Fresh game world: in the VM, `nix run .#reset-local`.


### Development
Useful context to give your agent.

# Klanker Kontext

I cloned several repos and fed them to the agent during the process of building this project.
You should do the same.

The screeps [server](https://github.com/screeps/screeps.git)

[backend-local](https://github.com/screeps/backend-local.git)
Contains an HTTP server accessed by clients and a CLI
server for administration.

[driver](https://github.com/screeps/driver.git)
a link between the environment-independent engine (that is shared for the
official server, standalone server, and in-browser simulation) and the
immediate environment that hosts the game engine.

[render](https://github.com/screeps/renderer.git)
This library is based on [PixiJS](https://pixijs.com/) and contains the renderer engine used in the Screeps game.

[tutorial scripts](https://github.com/screeps/tutorial-scripts.git)
The original tutorial scripts.

[typed-screeps](https://github.com/screepers/typed-screeps.git)
Strong TypeScript declarations for the game Screeps: World.

[paradox](https://gitlab.com/paradox_labs/paradox.git)
A language for domain specification.

# Install and Run
Clone the [repo](https://gitlab.com/dox-populi/screeps) and follow the instructions in README.md.
