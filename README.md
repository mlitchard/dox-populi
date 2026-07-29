# dox-populi

A Screeps client whose creep population is governed by a [Paradox](https://gitlab.com/paradox_labs/paradox)
`.dox` specification: Paradox generates the typed decision logic, nix owns the
generate → typecheck → bundle pipeline, and a private Screeps server runs the
result.

The server is the **open-source Screeps server, nix-vendored** — no Steam
install is needed to build or run it. You only need your own Steam copy of
the game to *watch* the world, through either the Steam client or the
browser client bridge (which serves the official client assets from your
Steam install).

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

Prerequisites: nix with flakes enabled. (Steam + the game are only needed
for watching, step 4.)

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

   Self-provisioning: creates the account (from `SCREEPS_LOCAL_CREDS` or
   `SCREEPS_LOCAL_EMAIL`/`SCREEPS_LOCAL_PASSWORD`), pushes `main.js`, and
   auto-places `Spawn1` if the account owns nothing.

   ✅ Output ends with `deployed main.js ...` and either `world-status:
   normal` or `auto-placed Spawn1 in <room>`.

4. **Watch it play** (optional — needs your Steam copy of the game)

   - Browser: `nix run .#client`, then open
     `http://127.0.0.1:8080/(http://127.0.0.1:21025)/` and sign in with
     your deploy-local credentials. Reads the client assets from your Steam
     install (`SCREEPS_CLIENT_NW` to override the path).
   - Or Steam client → Screeps → *Private server* → `127.0.0.1:21025`.

5. **Useful knobs**

   ```sh
   nix run .#cli           # server CLI (port 21026)
   nix run .#stop          # stop server + client, world kept
   nix run .#reset-local   # stop + wipe the world (fresh on next start)
   nix flake check         # spec-check, typecheck, build, itest, vm-boot
   ```

---

## Quickstart — other Linux (no nix required)

Nothing is built on your machine: nix lives **inside** a dev VM that installs
itself. Host prerequisites: `qemu`, `tmux`, `curl`.

1. **Get the installer ISO**

   Download `dox-populi-installer.iso` from the project releases and place it
   next to `run-vm.sh` (or `export ISO_URL=<release-url>` and the script
   downloads it). Maintainers build it with `nix build .#installer-iso`.

2. **Put your key in the shared directory**

   ```sh
   mkdir -p ~/vm-keys
   cp /path/to/your/key ~/vm-keys/identity
   ```

   The directory you pass as `WORKDIR` appears inside the VM at `~/work`,
   so your key is found at its conventional path `~/work/identity`
   automatically.

3. **Install the VM (fully automatic)**

   ```sh
   WORKDIR=$HOME/vm-keys ./run-vm.sh
   ./run-vm.sh console        # watch; Ctrl-b d detaches
   ```

   The installer partitions the virtual disk, builds the whole dev
   environment inside the VM, and powers off.

   ✅ Console ends with `install complete — powering off`, then
   `[qemu exited: 0]`.

4. **Boot and log in**

   ```sh
   WORKDIR=$HOME/vm-keys ./run-vm.sh     # WORKDIR needed on every start
   ssh -p 2222 dev@localhost             # password: dox-populi
   ```

   ✅ `ls ~/work/identity` shows your key.

   > **Note — `REMOTE HOST IDENTIFICATION HAS CHANGED!`**: every VM
   > (re)install generates fresh SSH host keys, so after a factory reset
   > or `INSTALL=1` your `known_hosts` still pins the old VM's key and
   > ssh refuses to connect. Not an attack — evict the stale entry and
   > retry:
   >
   > ```sh
   > ssh-keygen -R '[localhost]:2222'
   > ```

5. **Start the server and deploy** (inside the VM)

   ```sh
   cd ~/dox-populi
   nix develop        # first run builds everything, takes a while
   nix run .#server
   ```

   The VM binds `0.0.0.0` and run-vm.sh forwards 21025/21026 to the host.

   ✅ On the **host**: `curl -s http://localhost:21025/api/version` returns
   JSON.

   Then, still in the VM: `nix run .#deploy-local`.

6. **Watch it play**

   - Steam client on the **host** → Screeps → *Private server* →
     `localhost:21025`.
   - Or the browser client: if the game is in the host's default Steam
     library (or `SCREEPS_CLIENT_NW` points at its `package.nw`),
     run-vm.sh automatically links it into your `WORKDIR` share. In the
     VM run `nix run .#client`, then on the host open
     `http://localhost:8080/(http://127.0.0.1:21025)/` and sign in with
     your deploy-local credentials.

### VM management

```sh
./run-vm.sh            # start (detached)
./run-vm.sh console    # serial console (Ctrl-b d = detach)
./run-vm.sh send CMD   # type a command into the console
./run-vm.sh status     # running?
./run-vm.sh kill       # stop
```

Knobs: `MEM`, `CPUS`, `DISK`, `DISK_SIZE`, `WORKDIR`, `ISO`, `ISO_URL`,
`INSTALL=1` (force reinstall boot). Factory reset: `rm dox-populi.qcow2`.
Fresh game world: in the VM, `nix run .#reset-local`.
