## The Postscript

Objective 1 was onboarding: one host dependency, proven by doing it.

**The exercise.** QEMU is the one dependency.

1. Download the installer ISO.
   <!-- TODO: Hetzner release link, pinned at release time -->

2. Create a disk and boot the installer:

   ```
   qemu-img create -f qcow2 dox-populi.qcow2 40G
   qemu-system-x86_64 -m 4G -smp 4 \
     -drive file=dox-populi.qcow2,if=virtio,format=qcow2 \
     -cdrom dox-populi-installer.iso -boot d \
     -display none -serial mon:stdio
   ```

   The installer copies the system onto the disk and powers itself off.
   You watch it happen on the serial console; you touch nothing.

3. Boot the installed system:

   ```
   qemu-system-x86_64 -m 32G -smp 8 \
     -drive file=dox-populi.qcow2,if=virtio,format=qcow2 \
     -netdev user,id=net0,hostfwd=tcp::21025-:21025,hostfwd=tcp::8080-:8080 \
     -device virtio-net-pci,netdev=net0 \
     -display none -serial mon:stdio
   ```

   The serial console logs you in as `dev`.

4. Find the world ticking. From the host:

   ```
   curl http://localhost:21025/api/version
   ```

   Or watch it: inside the VM, `nix run .#client` serves the browser
   client; open http://localhost:8080 on the host.

What you just learned: onboarding took one host dependency.

Objective 2 was equipment: what the rest of the series requires and why.

**The equipment.** Download the context sources — the same material I fed
the LLM while building this project, and what you feed yours when you
interrogate the spec:

- Paradox: https://gitlab.com/paradox_labs/paradox
- the official Screeps tutorial sources
  <!-- TODO: pin exact link at draft time -->
- typed-screeps, the ambient Screeps API types
  <!-- TODO: pin exact link at draft time -->

Later posts assume you have these.

Before the next post: open `dox/creeps.dox` in the VM and look around.
Post one teaches interrogation; bring a question.

---

In 1986 Fred Brooks wrote
[No Silver Bullet](https://en.wikipedia.org/wiki/No_Silver_Bullet):
there is no single development that promises even one order-of-magnitude
improvement, because the difficulty of software divides into the
accidental and the essential, and the essential does not yield to tools.
The confluence attacks the
accidental — the environment that won't reproduce, the case nobody
considered, the transcription from decision to code. The essential stayed
human in every transcript this series will show you: what the bot should
do, what fit for purpose means, when the green check deserves a second
look. What grows is what you can deliver with confidence.
