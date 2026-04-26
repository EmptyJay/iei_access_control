#!/usr/bin/env bash
# usb_backup.sh — triggered by udev when a USB drive labelled ERCBACKUP is plugged in.
# Called by systemd-run with the device node as $1 (e.g. /dev/sda1).
#
# ONE-TIME SETUP (run on Pi as root after deploy):
#   sudo mkdir -p /mnt/iei-backup
#   sudo cp /opt/iei/etc/99-iei-backup.rules /etc/udev/rules.d/
#   sudo chmod +x /opt/iei/bin/usb_backup.sh
#   sudo udevadm control --reload-rules
#
# FLASH DRIVE SETUP (format with label ERCBACKUP):
#   Mac:   diskutil eraseDisk FAT32 ERCBACKUP /dev/diskN
#   Linux: mkfs.vfat -n ERCBACKUP /dev/sdX

set -euo pipefail

DEVICE="${1:?device node required}"
MOUNT="/mnt/iei-backup"
LOG="/var/log/iei-backup.log"
APP="/opt/iei"
APP_USER="ercadmin"

exec >> "$LOG" 2>&1

echo ""
echo "=== $(date '+%Y-%m-%d %H:%M:%S') USB backup started for $DEVICE ==="

mkdir -p "$MOUNT"

if ! mount "$DEVICE" "$MOUNT"; then
  echo "ERROR: failed to mount $DEVICE"
  exit 1
fi

su -s /bin/bash "$APP_USER" -c \
  "cd $APP && RAILS_ENV=production bin/rails 'backup:usb[$MOUNT]'"

sync
umount "$MOUNT"

echo "=== Backup complete ==="
