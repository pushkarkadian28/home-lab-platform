#!/usr/bin/env bash
# Snapshots named Docker volumes and syncs them to external storage.
# Run via cron. Adjust BACKUP_DEST for your environment.

set -euo pipefail

BACKUP_ROOT="/home/youruser/backups"
BACKUP_DEST="/mnt/external-drive/homelab-backups"
DATE=$(date +%Y-%m-%d)
STACK_DIR="/home/youruser/home-lab-platform"

mkdir -p "${BACKUP_ROOT}/${DATE}"

cd "${STACK_DIR}"

# Stop only the databases briefly for a consistent snapshot.
# Applications keep running against cached state during this window.
docker compose stop nextcloud-db immich-db paperless-db

for volume in nextcloud-data nextcloud-db vaultwarden-data immich-data immich-db paperless-data paperless-db; do
  docker run --rm \
    -v "home-lab-platform_${volume}:/source:ro" \
    -v "${BACKUP_ROOT}/${DATE}:/backup" \
    alpine \
    tar czf "/backup/${volume}.tar.gz" -C /source .
done

docker compose start nextcloud-db immich-db paperless-db

rsync -a --delete "${BACKUP_ROOT}/${DATE}" "${BACKUP_DEST}/"

# Keep the last 14 daily backups locally.
find "${BACKUP_ROOT}" -maxdepth 1 -type d -mtime +14 -exec rm -rf {} \;

echo "Backup completed: ${DATE}"
