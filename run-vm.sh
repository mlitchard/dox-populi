#!/usr/bin/env bash
# dox-populi dev VM manager (dubai vm-session pattern): qemu runs
# detached in a tmux session with its serial console on stdio, and you
# connect to that console with `./run-vm.sh console` — a normal
# terminal you can cut/paste in, and detach from (Ctrl-b d) without
# stopping the VM.
#
# Host dependencies: qemu, tmux (+curl to download the ISO). NO nix —
# nix runs INSIDE the VM:
#
#   First run:  creates dox-populi.qcow2 (empty disk) and boots
#               dox-populi-installer.iso — an auto-installing ISO (the
#               dubai installer-auto-dd pattern) with this repo
#               embedded. Its systemd service partitions the disk,
#               nixos-installs the dev environment (built entirely by
#               the guest's nix), and powers off. Zero interaction —
#               watch progress with `./run-vm.sh console`.
#   After that: `./run-vm.sh` boots the installed system from disk.
#
# The ISO is built once by someone WITH nix:
#   nix build .#installer-iso   → result/iso/dox-populi-installer.iso
#
# Delete dox-populi.qcow2 for a factory reset.
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
# The Screeps server runs INSIDE the VM (install it there with
# fetch-screeps-server — your own Steam account); play by pointing the
# Steam client on the HOST at localhost:21025.
#
# Env knobs: MEM (default 8G), CPUS (default 4), DISK (default
# ./dox-populi.qcow2), DISK_SIZE (default 40G), WORKDIR (host dir
# shared into the guest at ~/work; default: none), INSTALL=1 (force an
# installer boot without recreating the disk).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
DISK="${DISK:-dox-populi.qcow2}"
DISK_SIZE="${DISK_SIZE:-40G}"
MEM="${MEM:-32G}"
CPUS="${CPUS:-8}"
ISO="${ISO:-$REPO/dox-populi-installer.iso}"
# Where non-nix users download the installer ISO from. Maintainer: after
# publishing the built ISO (nix build .#installer-iso) as a release
# asset, put its URL here so `./run-vm.sh` is fully self-serve.
ISO_URL="${ISO_URL:-}"
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

    # INSTALL=1 re-enters the installer without recreating the disk
    # (e.g. after aborting a first install).
    INSTALL="${INSTALL:-0}"
    if [ ! -f "$DISK" ]; then
      INSTALL=1
      qemu-img create -f qcow2 "$DISK" "$DISK_SIZE"
      echo "created $DISK ($DISK_SIZE)"
    fi
    if [ "$INSTALL" = 1 ] && [ ! -f "$ISO" ]; then
      # Maintainer convenience: pick up a freshly built ISO from
      # ./result (whatever nix named it).
      BUILT=$(set -- "$REPO"/result/iso/*.iso; [ -f "$1" ] && echo "$1")
      if [ -n "$BUILT" ]; then
        ISO="$BUILT"
      elif [ -n "$ISO_URL" ]; then
        echo "downloading the dox-populi installer ISO (one-time)..."
        curl -L -o "$ISO" "$ISO_URL"
      else
        cat >&2 <<EOF
error: installer ISO not found: $ISO

Download dox-populi-installer.iso from the project's releases and place
it next to this script (or set ISO_URL= to fetch it automatically).
Maintainers build it with: nix build .#installer-iso
EOF
        exit 1
      fi
    fi

    tmux new-session -d -s "$SESSION" \
      "INSTALL=$INSTALL DISK=$(printf %q "$DISK") MEM=$(printf %q "$MEM") \
       CPUS=$(printf %q "$CPUS") ISO=$(printf %q "$ISO") \
       QEMU=$(printf %q "$QEMU") \
       WORKDIR=$(printf %q "${WORKDIR:-}") $(printf %q "$0") _qemu"

    echo "VM started — serial console: $0 console   (Ctrl-b d = detach)"
    if [ "$INSTALL" = 1 ]; then
      cat <<EOF

First run: the installer runs by itself — no interaction needed. It
partitions the disk and builds the dev environment inside the VM
(takes a while). Watch progress: $0 console. The VM powers off when
the install finishes; then run $0 again to boot the installed system.
EOF
    fi
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

    # Optional host directory shared into the guest (9p, mounted at
    # /home/dev/work by the guest's fstab).
    SHARE=()
    if [ -n "${WORKDIR:-}" ]; then
      SHARE=(-virtfs "local,path=$WORKDIR,mount_tag=workdir,security_model=mapped-xattr")
    fi

    # Installer boot: the auto-installing ISO carries the repo source
    # inside it and does everything itself (see vm/installer.nix).
    INSTALLER=()
    if [ "${INSTALL:-0}" = 1 ]; then
      INSTALLER=(-cdrom "$ISO" -boot d)
    fi

    # Port forwards: 2222 -> sshd, 21025/21026 -> Screeps server + CLI
    # (the host Steam client connects to localhost:21025).
    "${QEMU:-qemu-system-x86_64}" \
      "${ACCEL[@]}" \
      -m "$MEM" -smp "$CPUS" \
      -drive "file=$DISK,if=virtio,format=qcow2" \
      -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::21025-:21025,hostfwd=tcp::21026-:21026 \
      -device virtio-net-pci,netdev=net0 \
      "${SHARE[@]}" \
      "${INSTALLER[@]}" \
      -display none \
      -serial mon:stdio \
      || { echo; echo "[qemu exited: $?] press Enter to close"; read -r; }
    ;;

  *)
    echo "usage: $0 [start|console|send <cmd>|status|kill]" >&2
    exit 1
    ;;
esac
