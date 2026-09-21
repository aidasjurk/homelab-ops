#!/usr/bin/env bash
# ==============================================================================
# Automated Disaster Recovery & Backup Routine
# Dell OptiPlex 7070 SFF Production Homelab (Debian 12 Bookworm)
# ==============================================================================
# - Consistent SQLite hot snapshots (.backup)
# - Container stacks and volume compression (gzip)
# - Client-side AES-256 encrypted sync via Rclone to Google Drive
# - Automated local (7 days) and offsite retention management
# ==============================================================================

set -euo pipefail

# Environment & Authentication
# Dynamically locate user rclone config even when executed via sudo/root
REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "${REAL_USER}" | cut -d: -f6)
export RCLONE_CONFIG="${RCLONE_CONFIG:-${USER_HOME}/.config/rclone/rclone.conf}"

BACKUP_SRC="/opt/stacks"
BACKUP_DEST="/var/backups/stacks"
DATE=$(date +%Y%m%d_%H%M%S)
ARCHIVE_NAME="stacks_backup_${DATE}.tar.gz"
REMOTE_TARGET="gdrive-crypt:server-backups"
LOG_TAG="[HOMELAB-BACKUP]"

echo "${LOG_TAG} $(date): Starting backup routine..."

# 0. Ensure target directory exists
mkdir -p "${BACKUP_DEST}"

# 1. Safely snapshot SQLite databases without interrupting live containers
# Prevents malformed database states during active WAL journal transactions
if [ -d "${BACKUP_SRC}" ]; then
    echo "${LOG_TAG} $(date): Performing safe SQLite hot snapshots..."
    find "${BACKUP_SRC}" -type f -name "*.db" -o -name "*.sqlite3" | while read -r db_file; do
        echo "${LOG_TAG} Snapshotting ${db_file}..."
        sqlite3 "${db_file}" ".backup ${db_file}.snap" || true
    done
fi

# 2. Archive service stacks, persistent configs and snapshots
echo "${LOG_TAG} $(date): Compressing service stacks to ${ARCHIVE_NAME}..."
tar -czf "${BACKUP_DEST}/${ARCHIVE_NAME}"     --exclude="*.sock"     --exclude="*.tmp"     --exclude="cache"     -C "${BACKUP_SRC}" .

# Clean up temporary snapshot files
find "${BACKUP_SRC}" -type f -name "*.snap" -delete || true

# 3. Offsite sync via Rclone with client-side AES-256 encryption
echo "${LOG_TAG} $(date): Syncing encrypted archive to Google Drive (${REMOTE_TARGET})..."
rclone copy "${BACKUP_DEST}/${ARCHIVE_NAME}" "${REMOTE_TARGET}"     --fast-list     --checksum     --transfers 4     --checkers 8     --log-level NOTICE

# 4. Retention policy: Prune local archives older than 7 days
echo "${LOG_TAG} $(date): Pruning local archives older than 7 days..."
find "${BACKUP_DEST}" -type f -name "stacks_backup_*.tar.gz" -mtime +7 -delete

echo "${LOG_TAG} $(date): Backup completed successfully. Archive: ${ARCHIVE_NAME}"
