# dox-populi

A Screeps client whose creep population is governed by a [Paradox](https://gitlab.com/paradox_labs/paradox)
`.dox` specification: Paradox generates the typed decision logic, nix owns the
generate → typecheck → bundle pipeline, and a private Screeps server (your own
Steam copy) runs the result.

You play by pointing the **Steam Screeps client at `localhost:21025`** — the
server runs headless, either natively (NixOS/nix users) or inside a
self-installing dev VM (everyone else).

---

## Your encryption key

All secrets in `secrets/` are age files managed with **secrix**. Apps decrypt
them with **your** key.

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
secrix create secrets/STEAM_TOKEN -i /path/to/your/key -r "$(cat /path/to/your/key.pub)"
```

---

## Quickstart — NixOS (or any Linux with nix + flakes)

Prerequisites: nix with flakes enabled, Steam with **Screeps purchased and
installed** (the server ships inside the game bundle).

1. **Clone and enter the dev shell**

   ```sh
   git clone <this-repo> && cd dox-populi
   nix develop        # or `direnv allow`
   ```

   ✅ A command menu prints.

2. **Provide your key**

   ```sh
   export SCREEPS_IDENTITY=/path/to/your/key
   ```

   ✅ `secrix decrypt secrets/STEAM_TOKEN -i "$SCREEPS_IDENTITY"` prints a
   value. ❌ If not, re-encrypt it to your key (see above).

3. **Start the private server**

   ```sh
   nix run .#server
   ```

   Uses the Steam-installed server (default
   `~/.local/share/Steam/steamapps/common/Screeps/server`; override with
   `STEAM_SCREEPS_DIR`). Binds loopback by default (`SCREEPS_HOST` to change).

   ✅ `curl -s http://127.0.0.1:21025/api/version` returns JSON.

4. **Play and deploy**

   - Steam client → Screeps → *Private server* → `127.0.0.1:21025`; create
     your player and place a spawn.
   - `nix run .#deploy-local` — bundles and pushes `main.js` to the local
     server.

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

5. **Install the Screeps server** (your Steam account — you must own the game)

   ```sh
   fetch-screeps-server
   ```

   ✅ `ls ~/screeps/server/resources/node` exists.

6. **Start the server**

   ```sh
   cd ~/dox-populi
   nix develop        # first run builds everything, takes a while
   nix run .#server
   ```

   ✅ On the **host**: `curl -s http://localhost:21025/api/version` returns
   JSON.

7. **Play and deploy**

   - Steam client **on the host** → Screeps → *Private server* →
     `localhost:21025`; create your player and place a spawn.
   - In the VM: `nix run .#deploy-local`.

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
Fresh game world: in the VM, stop the server and `rm -rf ~/dox-populi/.server-data`.
