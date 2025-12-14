#!/usr/bin/env bash
set -euo pipefail

echo "Starting bootstrap..."

# Require root (cloud-init runs as root, but this prevents accidental misuse)
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Variables
DATA_DISK="/dev/disk/azure/scsi1/lun0"
MOUNT_POINT="/mnt/mcdata"
WORLD_DIR="$MOUNT_POINT/world"

BOOTSTRAP_STATE_DIR="/var/lib/minecraft"
BOOTSTRAP_MARKER="$BOOTSTRAP_STATE_DIR/bootstrap_done"

MC_ROOT="/opt/minecraft"
MC_WORLD="$MC_ROOT/world"

# cloud-init should place this file here before running this script
SERVICE_SRC="$MC_ROOT/minecraft.service"

# Update OS packages
apt update
apt upgrade -y

# Install required packages
apt install -y curl wget unzip ca-certificates

# Install Java (LTS) + Python runtime for apply.py
apt install -y openjdk-21-jre-headless python3.12 python3.12-venv python3-pip

# Create the minecraft group and user (idempotent)
getent group minecraft >/dev/null 2>&1 || groupadd --system minecraft
id minecraft >/dev/null 2>&1 || useradd \
  --system \
  --home-dir "$MC_ROOT" \
  --shell /usr/sbin/nologin \
  --gid minecraft \
  minecraft

# Create necessary directories
mkdir -p \
  "$MC_ROOT" \
  "$MC_ROOT/server" \
  "$MC_ROOT/plugins" \
  "$MC_ROOT/config" \
  "$MC_WORLD" \
  /var/log/minecraft \
  "$MOUNT_POINT"

# Set ownership + permissions
chown -R minecraft:minecraft "$MC_ROOT" /var/log/minecraft

# Permissions
# - Directories under $MC_ROOT should be accessible to the minecraft user/group.
# - Files (especially systemd unit files) should not accidentally become executable.
chmod 750 \
  "$MC_ROOT" \
  "$MC_ROOT/server" \
  "$MC_ROOT/plugins" \
  "$MC_ROOT/config" \
  "$MC_WORLD" \
  /var/log/minecraft

# Verify user/group
id minecraft
getent passwd minecraft
getent group minecraft

# Verify data disk presence
if [[ ! -b "$DATA_DISK" ]]; then
  echo "ERROR: Expected data disk device not found at $DATA_DISK"
  exit 1
fi

# Format the disk only if needed
if ! blkid "$DATA_DISK" >/dev/null 2>&1; then
  echo "Formatting data disk $DATA_DISK with ext4..."
  mkfs.ext4 "$DATA_DISK"
else
  echo "Data disk $DATA_DISK already formatted."
fi

# Mount the data disk
mkdir -p "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
  if ! mount "$DATA_DISK" "$MOUNT_POINT"; then
    echo "ERROR: Failed to mount $DATA_DISK at $MOUNT_POINT"
    exit 1
  fi
fi

# Persist the mount in /etc/fstab
UUID="$(blkid -s UUID -o value "$DATA_DISK")"

if [[ -z "$UUID" ]]; then
  echo "ERROR: Unable to retrieve UUID for $DATA_DISK"
  exit 1
fi

grep -q "$UUID" /etc/fstab || \
  echo "UUID=$UUID  $MOUNT_POINT  ext4  defaults,nofail  0  2" | tee -a /etc/fstab >/dev/null

# Create the world directory on the disk
mkdir -p "$WORLD_DIR"

# Ensure Minecraft-side mount target exists
mkdir -p "$MC_WORLD"

# Bind-mount world directory into Minecraft path
if ! mountpoint -q "$MC_WORLD"; then
  if ! mount --bind "$WORLD_DIR" "$MC_WORLD"; then
    echo "ERROR: Failed to bind mount $WORLD_DIR to $MC_WORLD"
    exit 1
  fi
fi

# Persist the bind mount
grep -q "$WORLD_DIR $MC_WORLD" /etc/fstab || \
  echo "$WORLD_DIR  $MC_WORLD  none  bind  0  0" | tee -a /etc/fstab >/dev/null

# Set ownership after mounts
# Avoid expensive recursive chown on every boot; only do it on first bootstrap.
mkdir -p "$BOOTSTRAP_STATE_DIR"
chmod 750 "$BOOTSTRAP_STATE_DIR"

if [[ ! -f "$BOOTSTRAP_MARKER" ]]; then
  chown -R minecraft:minecraft "$WORLD_DIR" "$MC_WORLD"

  if ! chown minecraft:minecraft "$WORLD_DIR" "$MC_WORLD"; then
    echo "WARNING: Failed to chown $WORLD_DIR and $MC_WORLD to minecraft:minecraft (non-fatal)" >&2
  fi
  touch "$BOOTSTRAP_MARKER"
  chmod 640 "$BOOTSTRAP_MARKER"
else
  chown minecraft:minecraft "$WORLD_DIR" "$MC_WORLD" || true
fi

# Install systemd service (assumes cloud-init placed it at $SERVICE_SRC)
if [[ ! -f "$SERVICE_SRC" ]]; then
  echo "ERROR: Expected service file at $SERVICE_SRC"
  exit 1
fi

cp "$SERVICE_SRC" /etc/systemd/system/minecraft.service

# Systemd unit files should be world-readable and owned by root.
chown root:root /etc/systemd/system/minecraft.service
chmod 0644 /etc/systemd/system/minecraft.service

systemctl daemon-reload
systemctl enable minecraft

echo "Bootstrap complete."
