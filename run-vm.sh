#!/usr/bin/env bash
# dox-populi dev VM runner (dubai vm-session pattern): qemu runs
# detached in a tmux session with its serial console on stdio, and you
# connect to that console with `./run-vm.sh console` — a normal
# terminal you can cut/paste in, and detach from (Ctrl-b d) without
# stopping the VM.
#
# This script only RUNS the VM. Provisioning is the flake's job:
#
#   nix run .#installer-iso   one-time: creates dox-populi.qcow2 and
#                             boots the auto-installing ISO, whose boot
#                             service dd's the prebuilt system image
#                             onto the disk and powers off
#   ./run-vm.sh               boots the installed system from disk
#
# Host dependencies: qemu, tmux. No nix needed to RUN the VM — nix
# runs INSIDE it.
#
# Delete dox-populi.qcow2 for a factory reset (then reinstall).
#
# Commands:
#   ./run-vm.sh [start]      start the VM (detached)
#   ./run-vm.sh console      connect to the serial console (Ctrl-b d = detach)
#   ./run-vm.sh send <cmd>   type a command into the console
#   ./run-vm.sh status       is the VM running?
#   ./run-vm.sh kill         stop the VM
#
# The guest is a full NixOS dev environment (see vm/module.nix). Log in
# on the serial console (auto-login as `dev`) or:
#
#   ssh -p 2222 dev@localhost   # password: dox-populi
#
# The Screeps server runs INSIDE the VM (nix run .#server — the
# nix-vendored open-source server, pre-baked into the image); play by
# pointing the Steam client on the HOST at localhost:21025.
#
# Env knobs: MEM (default 32G), CPUS (default 8), DISK (default
# ./dox-populi.qcow2), WORKDIR (host dir shared into the guest at
# ~/work; default: ~/vm-keys, skipped if it doesn't exist).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DISK="${DISK:-dox-populi.qcow2}"
# Host dir shared into the guest at ~/work (keys, client assets).
# Skipped if the directory doesn't exist.
WORKDIR="${WORKDIR:-$HOME/vm-keys}"
MEM="${MEM:-32G}"
CPUS="${CPUS:-8}"
SESSION="${SESSION:-dox-populi-vm}"

CMD="${1:-start}"
[ $# -gt 0 ] && shift

case "$CMD" in

  console)
    exec tmux attach-session -t "$SESSION"
    ;;

  send)
    exec tmux send-keys -t "$SESSION" "$*" C-m
    ;;

  status)
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "running (connect: $0 console)"
    else
      echo "not running"
    fi
    exit 0
    ;;

  kill)
    # Kill the tmux session (takes qemu with it) and reap any stray
    # qemu on our disk from older runs outside tmux.
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    pkill -f "qemu-system-x86_64.*$DISK" 2>/dev/null || true
    echo "stopped"
    exit 0
    ;;

  start)
    if ! command -v tmux >/dev/null 2>&1; then
      echo "error: tmux is required (it hosts the VM's serial console)" >&2
      exit 1
    fi
    # Resolve qemu HERE and hand the absolute path into the tmux
    # session: tmux spawns sessions with its own environment, which may
    # not have this shell's PATH (e.g. qemu from a dev shell).
    if ! QEMU="$(command -v qemu-system-x86_64)"; then
      echo "error: qemu-system-x86_64 is required (install qemu on the host)" >&2
      exit 1
    fi
    if tmux has-session -t "$SESSION" 2>/dev/null; then
      echo "already running — connect: $0 console"
      exit 0
    fi

    # Running is this script's ONLY job — provisioning belongs to the
    # flake. No disk means not installed; refuse, don't improvise.
    if [ ! -f "$DISK" ]; then
      cat >&2 <<EOF
error: no VM disk at $DISK

Provision it first (one-time): nix run .#installer-iso
EOF
      exit 1
    fi

    tmux new-session -d -s "$SESSION" \
      "DISK=$(printf %q "$DISK") MEM=$(printf %q "$MEM") \
       CPUS=$(printf %q "$CPUS") \
       QEMU=$(printf %q "$QEMU") \
       WORKDIR=$(printf %q "${WORKDIR:-}") $(printf %q "$0") _qemu"

    echo "VM started — serial console: $0 console   (Ctrl-b d = detach)"
    exit 0
    ;;

  # Internal: runs qemu in the foreground of the tmux session, serial
  # console on stdio.
  _qemu)
    # Hardware acceleration where available; TCG emulation otherwise.
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

    # The repo itself, shared read-write into the guest (9p, mounted at
    # /home/dev/dox-populi by the guest's fstab): the guest works on the
    # host's REAL working tree — history, branches, remote and all.
    SHARE=(-virtfs "local,path=$REPO,mount_tag=repodir,security_model=mapped-xattr")

    # Optional host directory shared into the guest (9p, mounted at
    # /home/dev/work by the guest's fstab).
    if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
      SHARE+=(-virtfs "local,path=$WORKDIR,mount_tag=workdir,security_model=mapped-xattr")

      # Browser-client assets: put the game's package.nw in the shared
      # dir so `nix run .#client` inside the VM finds it (~/work/package.nw).
      # A symlink would dangle — the guest resolves symlink targets in
      # its OWN namespace — so hard-link it (same inode, served as a
      # regular file), falling back to a copy across filesystems.
      # Re-linked whenever Steam replaces the file (new inode).
      NW="${SCREEPS_CLIENT_NW:-$HOME/.local/share/Steam/steamapps/common/Screeps/package.nw}"
      if [ -f "$NW" ]; then
        NW=$(readlink -f "$NW")
        if ! [ "$WORKDIR/package.nw" -ef "$NW" ]; then
          ln -f "$NW" "$WORKDIR/package.nw" 2>/dev/null \
            || cp -f "$NW" "$WORKDIR/package.nw"
          echo "linked client assets into $WORKDIR/package.nw"
        fi
      fi
    fi

    # Port forwards: 2222 -> sshd, 21025/21026 -> Screeps server + CLI
    # (the host Steam client connects to localhost:21025), 8080 -> the
    # browser client bridge (nix run .#client inside the VM).
    "${QEMU:-qemu-system-x86_64}" \
      "${ACCEL[@]}" \
      -m "$MEM" -smp "$CPUS" \
      -drive "file=$DISK,if=virtio,format=qcow2" \
      -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::21025-:21025,hostfwd=tcp::21026-:21026,hostfwd=tcp::8080-:8080 \
      -device virtio-net-pci,netdev=net0 \
      "${SHARE[@]}" \
      -display none \
      -serial mon:stdio \
      || { echo; echo "[qemu exited: $?] press Enter to close"; read -r; }
    ;;

  *)
    echo "usage: $0 [start|console|send <cmd>|status|kill]" >&2
    exit 1
    ;;
esac
