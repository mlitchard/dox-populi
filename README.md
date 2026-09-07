# dox-populi

A Screeps client whose creep population is governed by a [Paradox](https://gitlab.com/paradox_labs/paradox)
`.dox` specification: Paradox generates the typed decision logic, nix owns the
generate → typecheck → bundle pipeline, and a private Screeps server runs the
result.

Both the screeps server and viewer are open source and nix-vendored:
The whole stack builds from source and runs locally.

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
  1. `$SCREEPS_IDENTITY` 
  2. `$WORKDIR/identity`
  3. `~/work/identity` (the conventional location — in the VM this is the
     shared host directory, see below)

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

   Quickest — pass the credentials as env vars (single-quote a password
   with shell-special characters):

   ```sh
   SCREEPS_LOCAL_EMAIL=you SCREEPS_LOCAL_PASSWORD='your-password' \
     nix run .#deploy-local
   ```

   Durable — store them encrypted with secrix once, then deploy with no
   env vars:

   ```sh
   nix run .#deploy-local            # reads secrets/SCREEPS_LOCAL_CREDS
   ```

   `SCREEPS_IDENTITY=/path/to/your/key` names the key that decrypts it.
   See [docs/SECRIX.md](docs/SECRIX.md) for creating and editing that
   encrypted secret.

   Self-provisioning: creates the account and pushes `main.js`.

   ✅ Output ends with `deployed main.js ...`.

4. **Watch it play**

   `nix run .#client`, then open `http://127.0.0.1:8080/` and sign in
   with your deploy-local credentials. The viewer renders the world with
   the open-sourced renderer — no purchase. Place your spawn by clicking
   a tile, then watch the harvester spawn, harvest, and deliver.

5. **Useful knobs**

   ```sh
   nix run .#cli           # server CLI (port 21026)
   nix run .#stop          # stop server, world kept
   nix run .#reset-local   # stop + wipe the world (fresh on next start)
   nix flake check         # paradox-check, typecheck, build, vm-boot, run-vm-fresh
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

   start three ssh clients. One for the server, one for the client, and one for deploy.
   ```sh
   ssh -p 2222 dev@localhost             # password: dox-populi
   ```

   ✅ `ls ~/work/identity` shows your key.

   > **Note — `REMOTE HOST IDENTIFICATION HAS CHANGED!`**: every VM
   > (re)install generates fresh SSH host keys, so after a factory reset
   > your `known_hosts` still pins the old VM's key and
   > ssh refuses to connect. Evict the stale entry and retry
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

   In the VM run `nix run .#client`, then on the **host** open
   `http://localhost:8080/` and sign in with your deploy-local
   credentials. The viewer renders the world with the open-sourced
   renderer — no purchase, no Steam. Place your spawn by clicking a
   tile, then watch the harvester work.

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
