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

if ! mount -o "uid=$(id -u $APP_USER),gid=$(id -g $APP_USER)" "$DEVICE" "$MOUNT"; then
  echo "ERROR: failed to mount $DEVICE"
  exit 1
fi

APP_USER_HOME=$(getent passwd "$APP_USER" | cut -d: -f6)
RBENV_ROOT="$APP_USER_HOME/.rbenv"

python3 "$APP/bin/buzzer.py" 0.5 || true

su -s /bin/bash "$APP_USER" -c "
  export RBENV_ROOT=$RBENV_ROOT
  export PATH=$RBENV_ROOT/bin:$RBENV_ROOT/shims:\$PATH
  cd $APP
  RAILS_ENV=production bin/rails 'backup:usb[$MOUNT]'
"

# Deploy if ERC-Update.bundle is present on the drive
BUNDLE="$MOUNT/ERC-Update.bundle"
if [ -f "$BUNDLE" ]; then
  echo ""
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') Update bundle found — deploying ==="
  OLD_HEAD=$(git -C "$APP" rev-parse HEAD)
  DEPLOY_OK=true

  su -s /bin/bash "$APP_USER" -c "
    git -C $APP fetch $BUNDLE && git -C $APP merge --ff-only FETCH_HEAD
  " || DEPLOY_OK=false

  if $DEPLOY_OK; then
    su -s /bin/bash "$APP_USER" -c "
      export RBENV_ROOT=$RBENV_ROOT
      export PATH=$RBENV_ROOT/bin:$RBENV_ROOT/shims:\$PATH
      cd $APP
      RAILS_ENV=production bin/rails 'deploy:usb[$MOUNT]'
    " || DEPLOY_OK=false
  fi

  if $DEPLOY_OK; then
    echo "=== Deploy complete — restarting service ==="
    systemctl restart iei
  else
    echo "=== Deploy FAILED — rolling back to $OLD_HEAD ==="
    su -s /bin/bash "$APP_USER" -c "git -C $APP reset --hard $OLD_HEAD" || true
    su -s /bin/bash "$APP_USER" -c "
      export RBENV_ROOT=$RBENV_ROOT
      export PATH=$RBENV_ROOT/bin:$RBENV_ROOT/shims:\$PATH
      cd $APP
      RAILS_ENV=production bin/rails runner \
        'AccessEvent.create!(event_type: \"deploy_failed\", occurred_at: Time.current)'
    " || true
    systemctl restart iei
    echo "=== Rollback complete ==="
  fi
fi

sync
umount "$MOUNT"

python3 "$APP/bin/buzzer.py" 2.0 || true

echo "=== Backup complete ==="
