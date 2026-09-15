# dox-populi

dox-populi is an on-ramp into the benefits of formal methods, a study
in what they offer with an LLM agent in the loop. Until recently, the
tooling for formal methods was only available to a small group of
specialists. dox-populi uses
[Paradox](https://gitlab.com/paradox_labs/paradox),
[nix](https://docs.determinate.systems/), and an LLM agent to explore
the accessibility of this space: you prompt the agent, the agent
writes the spec, and the checker verifies it before code is generated.

This exploration happens primarily through building a system that delivers
typechecked javascript, with decision logic generated from a
consistency-checked spec, to a screeps server. Paradox provides a DSL whose
specs are checked for internal consistency: the bot's decisions are
written only as decision structure, a missed case comes back named,
and the validated spec generates the typed decision logic. nix is the
turnkey build: generate → typecheck → bundle. The LLM agent wrote the
spec and most of the infrastructure. You direct it and inspect what it
writes. Your Screeps server runs the result. Fire up the client and watch it go.

---

## Your encryption key

Secrets in `secrets/` are age files managed with **secrix** and
decrypted with your own SSH key. Before deploying, create a key and
encrypt the secrets so your key can open them —
[docs/SECRIX.md](docs/SECRIX.md) is the complete walkthrough.

---

## Quickstart — NixOS (or any Linux with nix + flakes)

Prerequisites: nix with flakes enabled.

1. **Clone and enter the dev shell**

   ```sh
   mkdir dox-populi && cd dox-populi
   git clone https://gitlab.com/dox-populi/screeps.git && cd screeps
   nix develop --builders ''
   ```

   ✅ A command menu prints.

2. **Start the server**

   ```sh
   nix run .#server --builders ''
   ```

   Fully nix-built; first run downloads and builds the server.
   Binds loopback by default; world state is in `.server-data/`.

   Check that the server is running:
   ✅ `curl -s http://127.0.0.1:21025/api/version` returns JSON.

3. **Deploy**

   ```sh
   nix run .#deploy-local            # reads secrets/SCREEPS_LOCAL_CREDS
   ```

   The decrypting key is found at `~/vm-keys/identity`, or set
   `SCREEPS_IDENTITY=/path/to/your/key`.
   See [docs/SECRIX.md](docs/SECRIX.md) for creating and editing that
   encrypted secret.

   Self-provisioning: creates the account, pushes `main.js` with its role modules,
   and auto-places `Spawn1`.

   Verify the deploy succeeded:
   ✅ Output ends with `auto-placed Spawn1 in <room>`.

4. **Watch it play**

   `nix run .#client`, then open `http://127.0.0.1:8080/` and sign in
   with your deploy-local credentials.

5. **Useful knobs**

   ```sh
   nix run .#cli           # server CLI (port 21026)
   nix run .#stop          # stop server + client, world kept
   nix run .#reset-local   # stop + wipe the world (fresh on next start)
   nix flake check         # all checks (itest and vm-boot each boot a VM)
   ```

---

## Quickstart — other Linux

The dev environment ships as a ready-to-boot VM image. You boot it
with [run-vm.sh](https://gitlab.com/dox-populi/screeps/-/raw/main/run-vm.sh) and work inside it. Host prerequisites: `qemu`, `tmux`.

1. **Put your key in the shared directory**

   ```sh
   mkdir -p ~/vm-keys
   cp /path/to/your/key ~/vm-keys/identity
   ```

   `~/vm-keys` (override with `WORKDIR=`) appears inside the VM at
   `~/vm-keys`, so your key is found at its conventional path
   `~/vm-keys/identity` automatically. Creating the key and encrypting
   the secrets is covered in [docs/SECRIX.md](docs/SECRIX.md).

2. **Boot the VM**

   ```sh
   ./run-vm.sh
   ./run-vm.sh console        # watch; Ctrl-b d detaches
   ```

3. **Log in**

   ```sh
   ssh -p 2222 dev@localhost             # password: dox-populi
   ```
   ✅ `ls ~/vm-keys/identity` shows your key.

   > **Note — `REMOTE HOST IDENTIFICATION HAS CHANGED!`**: every VM
   > reinstall generates fresh SSH host keys, so after a reinstall
   > your `known_hosts` still pins the old VM's key and
   > ssh refuses to connect. Evict the stale entry and retry.
   >
   > ```sh
   > ssh-keygen -R '[localhost]:2222'
   > ```

4. **Start the server and deploy**

   ```sh
   cd ~/dox-populi
   nix run .#server
   ```

   The VM binds `0.0.0.0` and run-vm.sh forwards 21025/21026 to the host.

   ✅ On the **host**: `curl -s http://localhost:21025/api/version` returns
   JSON.

   Then, still in the VM: `nix run .#deploy-local`.

5. **Watch it play**

   In the VM run `nix run .#client`, then on the **host** open
   `http://localhost:8080/` and sign in with your deploy-local
   credentials.

### VM management

```sh
./run-vm.sh            # start (detached)
./run-vm.sh console    # serial console (Ctrl-b d = detach)
./run-vm.sh send CMD   # type a command into the console
./run-vm.sh status     # running?
./run-vm.sh kill       # stop
```

### Development
Useful context to give your agent.

## Klanker Kontext

I cloned several repos and fed them to the agent during the process of building this project.
You should do the same.

The Screeps [server](https://github.com/screeps/screeps.git)
The standalone game server.

[backend-local](https://github.com/screeps/backend-local.git)
Contains an HTTP server accessed by clients and a CLI
server for administration.

[driver](https://github.com/screeps/driver.git)
A link between the environment-independent engine (that is shared for the
official server, standalone server, and in-browser simulation) and the
immediate environment that hosts the game engine.

[render](https://github.com/screeps/renderer.git)
This library is based on [PixiJS](https://pixijs.com/) and contains the renderer engine used in the Screeps game.

[tutorial scripts](https://github.com/screeps/tutorial-scripts.git)
The original tutorial scripts.

[typed-screeps](https://github.com/screepers/typed-screeps.git)
Strong TypeScript declarations for the game Screeps: World.

[paradox](https://gitlab.com/paradox_labs/paradox.git)
A system that generates clients in several different languages based on a single
specification.
