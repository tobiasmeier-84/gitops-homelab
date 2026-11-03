#!/bin/sh
# Worker of one backup run (ADR-0054). Runs in a pod that has the snapshot CLONE mounted read-only
# at /data and the per-app credentials in its environment.
#
#   1. prune by age (both chains): the privacy limit is enforced first, whatever happens later
#   2. one age key pair per chain, private keys stored in the vaults FIRST, read back and compared
#   3. tar | zstd | age (one ciphertext, two recipients) into /work/data.age, verified by decrypting
#      with the keys read back from the vaults
#   4. upload to both chains (chunks, size-verified, MANIFEST last)
#   5. prune by age again
# On any failure the keys and uploaded data of THIS run are removed and the age prune still runs.
# DRY_RUN=true only reads and verifies the archive stream: no keys, no uploads, no pruning.
#
# Exit 0 = both chains complete and nothing that should be gone is left; 1 otherwise.
# The last log line starts with "RESULT" and is picked up by the orchestrator for the mail.
# shellcheck disable=SC3040  # busybox ash (Alpine) supports pipefail
set -o pipefail

LIB_DIR="${LIB_DIR:-/scripts}"
DATA_DIR="${DATA_DIR:-/data}"
WORK="${WORK:-/work}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d-%H%M%S)}"   # UTC; the age of the backup is read from this
NAME="${APP_NAME}-${RUN_ID}"
CURRENT_NAME="$NAME"
export NAME CURRENT_NAME

# shellcheck source=/dev/null
. "$LIB_DIR/chain-lib.sh" || exit 1
tools_setup
aws_tune 2>/dev/null || true

if [ "${DRY_RUN:-false}" = "true" ]; then
  log "DRY RUN: reading $DATA_DIR through tar | zstd | zstd -t; no keys, no upload, no pruning"
  if tar -C "$DATA_DIR" -cf - . | "$ZSTD" -T2 | "$ZSTD" -t; then
    log "RESULT - dry run OK, the archive stream is valid ($(du -sk "$DATA_DIR" | cut -f1) KiB of data)"
    exit 0
  fi
  log "RESULT - dry run FAILED: the data could not be read as a valid archive"
  exit 1
fi

PRUNE_STATUS=ok
BACKUP_STATUS=failed
STORED_A=no
STORED_B=no
D="$WORK/stage"

prune_both() {
  for CHX in A B; do
    chain_prune_age "$CHX" || PRUNE_STATUS=FAILED
  done
}

on_exit() {
  rm -f /tmp/key-A.txt /tmp/key-B.txt /tmp/restore-A.key /tmp/restore-B.key /tmp/pub-A.txt /tmp/pub-B.txt
  if [ "$BACKUP_STATUS" != "complete" ]; then
    log "This run did not complete - removing its keys and data from the vaults and buckets"
    for CHX in A B; do
      if chain_setup "$CHX"; then
        chain_remove_backup "$CHX" "$NAME" || true
        key_del "$CHX" "$NAME" || true
      fi
    done
    if [ "$PRUNE_STATUS" = "ok" ]; then prune_both; fi   # the age limit also holds after a failure
  fi
  rm -rf "$D"
  log "RESULT - backup=$BACKUP_STATUS prune=$PRUNE_STATUS name=$NAME"
}
trap on_exit EXIT
trap 'exit 143' TERM INT

log "Backup $NAME (data as of snapshot $RUN_ID)"
mkdir -p "$D"

# 1. enforce the age limit first
prune_both
if [ "$PRUNE_STATUS" != "ok" ]; then log "WARNING: pruning failed - continuing with the backup, the run will be reported as failed"; fi

# 2. keys first, so an object can never exist without its key
for X in A B; do
  chain_setup "$X" || { log "FATAL: chain $X is not usable"; exit 1; }
  rm -f "/tmp/key-$X.txt"; "$AGE_KEYGEN" -o "/tmp/key-$X.txt" 2>"/tmp/keygen-$X.txt"
  grep "Public key:" "/tmp/keygen-$X.txt" | awk '{print $NF}' >"/tmp/pub-$X.txt"
  _priv=$(cat "/tmp/key-$X.txt")
  if [ ! -s "/tmp/pub-$X.txt" ] || [ -z "$_priv" ]; then log "FATAL: no key material for chain $X"; exit 1; fi
  key_put "$X" "$NAME" "$_priv" || { log "FATAL: storing the key for chain $X failed"; exit 1; }
  _back=$(key_get "$X" "$NAME") || _back=""
  [ "$_back" = "$_priv" ] || { log "FATAL: key read-back mismatch on chain $X"; exit 1; }
  log "Chain $X: key stored in the vault and read back identically"
done
PUB_A=$(cat /tmp/pub-A.txt); PUB_B=$(cat /tmp/pub-B.txt)

# 3. compress + encrypt (one ciphertext that either chain's key can open)
log "Compressing and encrypting $DATA_DIR -> $D/data.age"
tar -C "$DATA_DIR" -cf - . | "$ZSTD" -T2 | "$AGE" -r "$PUB_A" -r "$PUB_B" -o "$D/data.age" || { log "FATAL: archive pipeline failed"; exit 1; }
SIZE=$(stat -c%s "$D/data.age")
log "Encrypted archive: $SIZE bytes"
if [ "$SIZE" -lt 1024 ]; then log "FATAL: the archive is only $SIZE bytes - the read was cut short or the volume is empty"; exit 1; fi

# verify with the keys exactly as stored in the vaults
for X in A B; do
  chain_setup "$X"
  key_get "$X" "$NAME" >"/tmp/restore-$X.key"
done
log "Verifying: decrypting with the Chain A vault key, decompressing and walking the whole tar stream..."
"$AGE" -d -i /tmp/restore-A.key "$D/data.age" | "$ZSTD" -dc | tar -tf - >/dev/null || { log "FATAL: verification with the chain A key failed"; exit 1; }
log "Verifying that the Chain B vault key opens the same file..."
"$AGE" -d -i /tmp/restore-B.key "$D/data.age" | "$ZSTD" -dc | tar -tf - >/dev/null || { log "FATAL: verification with the chain B key failed"; exit 1; }
log "Verification passed"

# 4. upload to both chains
DATA_AS_OF="$RUN_ID"; export DATA_AS_OF
RC=0
for X in A B; do
  if upload_chain "$X" "$D" "$NAME"; then
    if [ "$X" = A ]; then STORED_A=yes; else STORED_B=yes; fi
  else
    RC=1
  fi
done
if [ "$RC" -ne 0 ] || [ "$STORED_A" != yes ] || [ "$STORED_B" != yes ]; then
  log "FATAL: at least one chain does not hold a complete copy"
  exit 1
fi
BACKUP_STATUS=complete

# 5. enforce the age limit again, now that the new backup exists
prune_both
if [ "$PRUNE_STATUS" != "ok" ]; then exit 1; fi
exit 0
