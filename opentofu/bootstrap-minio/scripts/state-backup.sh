#!/usr/bin/env bash
# Backs up the OpenTofu state bucket: mirrors bucket contents locally,
# archives, encrypts with a static age key, uploads to Backblaze B2,
# prunes local scratch space and old remote backups beyond retention.
#
# Simple, single-copy design — see ADR-0036 for why this differs from the
# dual-chain app-data backup design (ADR-0005).
set -euo pipefail

RETENTION_DAYS=30
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
SCRATCH_DIR=$(mktemp -d)
ARCHIVE_NAME="opentofu-state-${TIMESTAMP}.tar.zst"
ENCRYPTED_NAME="${ARCHIVE_NAME}.age"

cleanup() {
  rm -rf "${SCRATCH_DIR}"
}
trap cleanup EXIT

echo "[$(date -u)] Starting state bucket backup..."

mc mirror --quiet homelab/opentofu-state "${SCRATCH_DIR}/opentofu-state"

tar -C "${SCRATCH_DIR}" -cf - opentofu-state | zstd -q -o "${SCRATCH_DIR}/${ARCHIVE_NAME}"

age -r "$(cat /etc/state-backup/age-recipient.txt)" \
  -o "${SCRATCH_DIR}/${ENCRYPTED_NAME}" \
  "${SCRATCH_DIR}/${ARCHIVE_NAME}"

rclone --config /etc/state-backup/rclone.conf \
  copy "${SCRATCH_DIR}/${ENCRYPTED_NAME}" b2-state-backup:homelab-opentofu-state-backup/

CUTOFF=$(date -u -d "-${RETENTION_DAYS} days" +%Y%m%d 2>/dev/null || date -u -v-${RETENTION_DAYS}d +%Y%m%d)
rclone --config /etc/state-backup/rclone.conf \
  lsf b2-state-backup:homelab-opentofu-state-backup/ | while read -r f; do
    file_date=$(echo "$f" | grep -oP '\d{8}' | head -1)
    if [[ -n "$file_date" && "$file_date" < "$CUTOFF" ]]; then
      rclone --config /etc/state-backup/rclone.conf \
        deletefile "b2-state-backup:homelab-opentofu-state-backup/${f}"
      echo "Pruned old backup: ${f}"
    fi
  done

echo "[$(date -u)] Backup complete: ${ENCRYPTED_NAME}"