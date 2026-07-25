#!/usr/bin/env bash
# Launch the dox-populi dev VM. For people WITHOUT nix: the only host
# dependency is qemu. Someone with nix builds the image for you:
#
#   nix build .#vm-image        # result/nixos.qcow2
#
# then you run:
#
#   ./run-vm.sh path/to/nixos.qcow2
#
# The guest is a full NixOS dev environment (see vm/module.nix). Log in
# on the serial console (auto-login as `dev`) or:
#
#   ssh -p 2222 dev@localhost   # password: dox-populi
#
# The Screeps server runs INSIDE the VM (install it there with
# fetch-screeps-server — your own Steam account); play by pointing the
# Steam client on the HOST at localhost:21025.
#
# Env knobs: MEM (default 8G), CPUS (default 4), WORKDIR (host dir
# shared into the guest at ~/work; default: none).
set -euo pipefail

IMAGE="${1:-${IMAGE:-result/nixos.qcow2}}"
MEM="${MEM:-8G}"
CPUS="${CPUS:-4}"

if [ ! -f "$IMAGE" ]; then
  echo "error: VM image not found: $IMAGE" >&2
  echo "build it with: nix build .#vm-image   (or get the qcow2 from someone who can)" >&2
  echo "usage: $0 [path/to/nixos.qcow2]" >&2
  exit 1
fi

# Hardware acceleration where available; plain TCG emulation otherwise.
ACCEL=()
case "$(uname -s)" in
  Linux)
    if [ -w /dev/kvm ]; then
      ACCEL=(-enable-kvm -cpu host)
    else
      echo "warning: /dev/kvm not writable — running unaccelerated (slow)" >&2
    fi
    ;;
  Darwin)
    ACCEL=(-accel hvf -cpu host)
    ;;
esac

# Optional host directory shared into the guest (9p, mounted at
# /home/dev/work by the guest's fstab).
SHARE=()
if [ -n "${WORKDIR:-}" ]; then
  SHARE=(-virtfs "local,path=$WORKDIR,mount_tag=workdir,security_model=mapped-xattr")
fi

# Port forwards: 2222 -> sshd, 21025/21026 -> Screeps server + CLI (the
# host Steam client connects to localhost:21025).
exec qemu-system-x86_64 \
  "${ACCEL[@]}" \
  -m "$MEM" -smp "$CPUS" \
  -drive "file=$IMAGE,if=virtio,format=qcow2" \
  -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::21025-:21025,hostfwd=tcp::21026-:21026 \
  -device virtio-net-pci,netdev=net0 \
  "${SHARE[@]}" \
  -nographic
