#!/usr/bin/env bash
set -euo pipefail

# This script sets up a Debian 13 GNOME Wayland VM environment for neugaze development.
# It prepares the disk image and ISO, detects USB cameras for passthrough, and can optionally launch the VM installer.
# ~/vm-images/debian13-gnome-wayland.qcow2 will be created if it doesn't exist, and the Debian netinst ISO will be downloaded if not present.
VM_NAME=${VM_NAME:-neugaze-debian13}
IMAGE_DIR=${IMAGE_DIR:-/var/lib/libvirt/images/neugaze}
ISO_NAME=${ISO_NAME:-debian-13.5.0-amd64-netinst.iso}
ISO_URL=${ISO_URL:-https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/$ISO_NAME}
DISK_NAME=${DISK_NAME:-debian13-gnome-wayland.qcow2}
DISK_SIZE=${DISK_SIZE:-30G}
RAM=${RAM:-8192}
VCPUS=${VCPUS:-4}
OS_VARIANT=${OS_VARIANT:-debian13}
GRAPHICS=${GRAPHICS:-spice}
VIDEO=${VIDEO:-qxl}
CAMERA_VENDOR_ID=${CAMERA_VENDOR_ID:-}
CAMERA_PRODUCT_ID=${CAMERA_PRODUCT_ID:-}
AUTO_DETECT_CAMERA=${AUTO_DETECT_CAMERA:-true}

show_help() {
  cat <<'EOF'
Usage: neugaze-vm-setup.sh [--install] [--help]

Creates a Debian 13 GNOME Wayland VM environment for neugaze development.

Options:
  --install   Run qemu-system-x86_64 after preparing the disk and ISO.
  --help      Show this help message.

Environment variables:
  CAMERA_VENDOR_ID      USB camera vendor ID to passthrough to QEMU.
  CAMERA_PRODUCT_ID     USB camera product ID to passthrough to QEMU.
  AUTO_DETECT_CAMERA    When true, auto-detect a single USB camera if no IDs are provided.
EOF
}

ensure_command() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: required command '$cmd' not found." >&2
    exit 1
  }
}

normalize_id() {
  local id=$1
  if [[ -z "$id" ]]; then
    echo
    return
  fi
  if [[ "$id" == 0x* ]]; then
    echo "$id"
  else
    echo "0x$id"
  fi
}

detect_installed_debian() {
  local image=$1
  if ! command -v guestfish >/dev/null 2>&1; then
    return 1
  fi
  echo 'cat /etc/debian_version' | guestfish --ro -a "$image" -i 2>/dev/null | grep -q '.'
}

detect_camera() {
  local matches line count index choice
  matches=$(lsusb | grep -Ei 'camera|webcam|video|uvc|face|stream' || true)
  if [[ -z "$matches" ]]; then
    return 1
  fi

  count=$(printf '%s\n' "$matches" | grep -c '^')
  if [[ $count -eq 1 ]]; then
    line="$matches"
  else
    echo "Multiple USB video devices detected:" >&2
    index=1
    while IFS= read -r line; do
      printf '  %d) %s\n' "$index" "$line" >&2
      index=$((index + 1))
    done <<<"$matches"

    if [[ -t 0 ]]; then
      echo -n "Choose a device to passthrough [1-$count] (or press Enter to skip): " >&2
      read -r choice
      if [[ -z "$choice" ]]; then
        return 2
      fi
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 )) || (( choice > count )); then
        echo "Invalid selection." >&2
        return 2
      fi
      line=$(printf '%s\n' "$matches" | sed -n "${choice}p")
    else
      echo "Please set CAMERA_VENDOR_ID and CAMERA_PRODUCT_ID explicitly." >&2
      return 2
    fi
  fi

  if [[ "$line" =~ ID[[:space:]]([0-9a-fA-F]{4}):([0-9a-fA-F]{4}) ]]; then
    CAMERA_VENDOR_ID="0x${BASH_REMATCH[1]}"
    CAMERA_PRODUCT_ID="0x${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

INSTALL_VM=false
for arg in "$@"; do
  case $arg in
    --install)
      INSTALL_VM=true
      shift
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      show_help
      exit 1
      ;;
  esac
done

ensure_command qemu-img
ensure_command wget
ensure_command qemu-system-x86_64
ensure_command lsusb

if ! mkdir -p "$IMAGE_DIR" 2>/dev/null; then
  sudo mkdir -p "$IMAGE_DIR"
fi
cd "$IMAGE_DIR"

echo "[1/4] Preparing VM image directory: $IMAGE_DIR"

if [[ ! -f "$ISO_NAME" ]]; then
  echo "[2/4] Downloading Debian netinst ISO: $ISO_NAME"
  sudo wget -N "$ISO_URL"
else
  echo "[2/4] ISO already exists: $ISO_NAME"
fi

if [[ ! -f "$DISK_NAME" ]]; then
  echo "[3/4] Creating QCOW2 disk: $DISK_NAME ($DISK_SIZE)"
  sudo qemu-img create -f qcow2 "$DISK_NAME" "$DISK_SIZE"
else
  echo "[3/4] Disk already exists: $DISK_NAME"
fi

if [[ -z "$CAMERA_VENDOR_ID" && -z "$CAMERA_PRODUCT_ID" && "$AUTO_DETECT_CAMERA" == "true" ]]; then
  if detect_camera; then
    echo "[4/4] Auto-detected USB camera: vendor=$CAMERA_VENDOR_ID product=$CAMERA_PRODUCT_ID"
  else
    echo "[4/4] No single USB camera auto-detected; attach a camera or set CAMERA_VENDOR_ID/CAMERA_PRODUCT_ID." >&2
  fi
fi

CAMERA_VENDOR_ID=$(normalize_id "$CAMERA_VENDOR_ID")
CAMERA_PRODUCT_ID=$(normalize_id "$CAMERA_PRODUCT_ID")

IMAGE_INSTALLED=false
if [[ -f "$DISK_NAME" ]]; then
  if ! command -v guestfish >/dev/null 2>&1; then
    echo "[5/5] guestfish not installed; skipping Debian install detection."
  elif detect_installed_debian "$IMAGE_DIR/$DISK_NAME"; then
    IMAGE_INSTALLED=true
    echo "[5/5] Existing Debian installation detected in $DISK_NAME"
  else
    echo "[5/5] No existing Debian installation detected in $DISK_NAME"
  fi
fi

QEMU_BASE_CMD=(qemu-system-x86_64
  -name "$VM_NAME"
  -machine accel=kvm
  -smp "$VCPUS"
  -m "$RAM"
  -drive file="$IMAGE_DIR/$DISK_NAME",if=virtio,format=qcow2
  -display gtk
  -vga qxl
  -nic user,model=virtio
  -device qemu-xhci
)

QEMU_INSTALL_CMD=("${QEMU_BASE_CMD[@]}"
  -cdrom "$IMAGE_DIR/$ISO_NAME"
  -boot d
)

if [[ -n "$CAMERA_VENDOR_ID" && -n "$CAMERA_PRODUCT_ID" ]]; then
  QEMU_BASE_CMD+=( -device usb-host,vendorid="$CAMERA_VENDOR_ID",productid="$CAMERA_PRODUCT_ID" )
  QEMU_INSTALL_CMD+=( -device usb-host,vendorid="$CAMERA_VENDOR_ID",productid="$CAMERA_PRODUCT_ID" )
fi

cat <<EOF
The VM environment is ready.

EOF

if [[ "$IMAGE_INSTALLED" == true ]]; then
  cat <<EOF
The disk already appears to contain Debian.

To start the existing VM, run:

  ${QEMU_BASE_CMD[*]}

To reinstall Debian, run:

  ${QEMU_INSTALL_CMD[*]}
EOF
else
  cat <<EOF
To install Debian GNOME, run:

  ${QEMU_INSTALL_CMD[*]}
EOF
fi

if [[ "$INSTALL_VM" == true ]]; then
  if [[ "$IMAGE_INSTALLED" == true ]]; then
    echo "Existing Debian install detected; launching the VM from disk instead of booting the installer."
    exec "${QEMU_BASE_CMD[@]}"
  fi
  echo "Running QEMU installer..."
  exec "${QEMU_INSTALL_CMD[@]}"
fi
