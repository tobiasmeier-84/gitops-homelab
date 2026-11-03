#!/bin/sh
# One-off end-to-end check of the storage side of this app's backup (ADR-0054). No cluster data.
# Run it once after the credentials exist and after every change of the credentials or the library:
#   kubectl -n <ns> create job --from=cronjob/<app>-backup-selftest <app>-backup-selftest-1
#
#   A. age pruning against the REAL buckets and vaults: a fake backup stamped 20 days ago must be
#      deleted with its key from both chains, a fresh one must survive
#   B. restore round trip from both chains: the restored bytes equal the original
#   C. isolation: with this app's credentials, objects outside "<app>-" cannot be read, written or
#      deleted, the other apps' Azure vault is closed, and the Bitwarden machine account sees exactly
#      one project
# Everything it creates is removed again, also on failure. Exit 0 only if all checks pass.
# shellcheck disable=SC3040  # busybox ash (Alpine) supports pipefail
set -o pipefail

LIB_DIR="${LIB_DIR:-/scripts}"
# shellcheck source=/dev/null
. "$LIB_DIR/chain-lib.sh" || exit 1
tools_setup
aws_tune 2>/dev/null || true

FAIL=0
pass() { log "PASS: $*"; }
fail() { log "FAIL: $*"; FAIL=1; }

NOW_NAME="${APP_NAME}-$(date -u +%Y%m%d-%H%M%S)"
OLD_STAMP=$(date -u -d "@$(($(date -u +%s) - 20 * 86400))" +%Y%m%d-%H%M%S 2>/dev/null ||
  date -u -D %s -d "$(($(date -u +%s) - 20 * 86400))" +%Y%m%d-%H%M%S)
OLD_NAME="${APP_NAME}-${OLD_STAMP}"
export CURRENT_NAME=""
D=/tmp/selftest
mkdir -p "$D"

cleanup() {
  for X in A B; do
    if chain_setup "$X"; then
      for n in "$OLD_NAME" "$NOW_NAME"; do
        chain_remove_backup "$X" "$n" >/dev/null 2>&1 || true
        key_del "$X" "$n" >/dev/null 2>&1 || true
      done
    fi
  done
  rm -rf "$D" /tmp/restored-*.bin /tmp/key-*.txt /tmp/pub-*.txt
}
trap cleanup EXIT

put_backup() { # name  -> uploads a small encrypted backup of $D/payload to both chains, keys in both vaults
  _nm="$1"
  for X in A B; do
    chain_setup "$X" || return 1
    rm -f "/tmp/key-$X.txt"; "$AGE_KEYGEN" -o "/tmp/key-$X.txt" 2>"/tmp/keygen-$X.txt"
    grep "Public key:" "/tmp/keygen-$X.txt" | awk '{print $NF}' >"/tmp/pub-$X.txt"
    key_put "$X" "$_nm" "$(cat "/tmp/key-$X.txt")" || return 1
  done
  "$AGE" -r "$(cat /tmp/pub-A.txt)" -r "$(cat /tmp/pub-B.txt)" -o "$D/data.age" "$D/payload" || return 1
  for X in A B; do upload_chain "$X" "$D" "$_nm" || return 1; done
}

log "Preparing payload"
head -c 300000 /dev/urandom >"$D/payload"
ORIG=$(sha256sum "$D/payload" | awk '{print $1}')

# ---- A. age pruning against the real storage ------------------------------------------------
log "=== A. age pruning: a backup stamped $OLD_STAMP (20 days old) and a fresh one ==="
put_backup "$OLD_NAME" && put_backup "$NOW_NAME" || fail "could not create the two test backups"
for X in A B; do
  chain_prune_age "$X" || fail "chain $X: prune reported a problem"
  if chain_has_key "$X" "$OLD_NAME/MANIFEST"; then fail "chain $X: the 20-day-old backup is still in the bucket"; else pass "chain $X: old backup data deleted"; fi
  if key_names "$X" | grep -qx "$OLD_NAME"; then fail "chain $X: the old backup's key is still in the vault"; else pass "chain $X: old backup key deleted"; fi
  if chain_has_key "$X" "$NOW_NAME/MANIFEST"; then pass "chain $X: the fresh backup survived"; else fail "chain $X: the fresh backup was deleted"; fi
done

# ---- B. restore round trip --------------------------------------------------------------------
log "=== B. restore round trip ==="
for X in A B; do
  if chain_fetch "$X" "$NOW_NAME" "/tmp/restored-$X.bin" && [ "$(sha256sum "/tmp/restored-$X.bin" | awk '{print $1}')" = "$ORIG" ]; then
    pass "chain $X: restored bytes equal the original"
  else
    fail "chain $X: restore failed or differs"
  fi
done

# ---- C. isolation ---------------------------------------------------------------------------------
log "=== C. isolation of this app's credentials ==="
probe_denied() { # chain  (reading, writing and deleting outside the app's prefix must be denied)
  chain_setup "$1" || { fail "chain $1: setup"; return; }
  # Read: S3 answers 404 for a missing key whenever the credential may list the bucket (listing cannot
  # be limited to a prefix), so a missing key proves nothing. Try an EXISTING object of another app.
  _listok=no; _fk=""
  if _top=$("$AWS_PY" "$AWS" s3api list-objects-v2 --bucket "$C_BUCKET" --delimiter / --query 'CommonPrefixes[].Prefix' --output json --endpoint-url "$C_EP" 2>/dev/null); then
    _listok=yes
    _fk=$(printf '%s' "$_top" | "$JQ" -r --arg a "${APP_NAME}-" '.[]? | select(startswith($a) | not)' | head -n 1) || _fk=""
  fi
  _read=untested
  if [ -n "$_fk" ]; then
    for _o in MANIFEST 0001; do
      if "$AWS_PY" "$AWS" s3api head-object --bucket "$C_BUCKET" --key "${_fk}${_o}" --endpoint-url "$C_EP" >/dev/null 2>/tmp/head.err; then
        fail "chain $1: an object of another app (${_fk}${_o}) can be READ - access is not restricted to the prefix"; _read=failed; break
      fi
      case "$(cat /tmp/head.err)" in
        *"(403)"*|*"(401)"*|*Forbidden*|*AccessDenied*|*Unauthorized*) pass "chain $1: read of another app's object (${_fk}${_o}) is denied"; _read=ok; break ;;
      esac
    done
  fi
  if [ "$_read" = untested ]; then
    _err=$("$AWS_PY" "$AWS" s3api head-object --bucket "$C_BUCKET" --key "zz-isolation-probe-$$" --endpoint-url "$C_EP" 2>&1 >/dev/null) && fail "chain $1: HEAD outside the app prefix succeeded"
    case "$_err" in
      *"(403)"*|*"(401)"*|*Forbidden*|*AccessDenied*|*Unauthorized*) pass "chain $1: read outside the prefix is denied" ;;
      *"(404)"*|*NotFound*|*"Not Found"*)
        if [ "$_listok" = yes ]; then log "SKIP: chain $1: no object of another app in the bucket to test read isolation (listing is allowed, so 404 proves nothing)"
        else fail "chain $1: HEAD outside the prefix says 'not found' although listing is denied - unexpected"; fi ;;
      *) fail "chain $1: unexpected answer to the HEAD probe: $(echo "$_err" | head -c 200)" ;;
    esac
  fi
  printf x >/tmp/probe.bin
  if "$AWS_PY" "$AWS" s3api put-object --bucket "$C_BUCKET" --key "zz-isolation-probe-$$" --body /tmp/probe.bin --endpoint-url "$C_EP" >/dev/null 2>&1; then
    fail "chain $1: a WRITE outside the prefix succeeded (the probe object stays behind - delete it by hand)"
  else
    pass "chain $1: write outside the prefix is denied"
  fi
  if "$AWS_PY" "$AWS" s3api delete-object --bucket "$C_BUCKET" --key "zz-isolation-probe-$$" --endpoint-url "$C_EP" >/dev/null 2>&1; then
    fail "chain $1: a DELETE outside the prefix was accepted"
  else
    pass "chain $1: delete outside the prefix is denied"
  fi
}
probe_denied A
probe_denied B

if [ -n "${PROBE_OTHER_VAULT_URL:-}" ]; then
  _tok=$(az_token) || _tok=""
  if [ -n "$_tok" ]; then
    _code=$(curl_ca -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${_tok}" "${PROBE_OTHER_VAULT_URL}/secrets?api-version=7.4") || _code=000
    case "$_code" in
      401|403) pass "Azure: the other vault answers $_code (closed to this app)" ;;
      *) fail "Azure: the other vault ${PROBE_OTHER_VAULT_URL} answered $_code, expected 401/403" ;;
    esac
  else
    fail "Azure: no token, cannot probe"
  fi
else
  log "SKIP: no PROBE_OTHER_VAULT_URL set, the Azure isolation probe is not run"
fi

if bws_init; then
  _n=$(/tmp/bws project list 2>/dev/null | "$JQ" 'length') || _n=""
  if [ "$_n" = "1" ]; then pass "Bitwarden: the machine account sees exactly 1 project"; else fail "Bitwarden: the machine account sees '$_n' projects, expected 1"; fi
else
  fail "Bitwarden: could not initialise bws"
fi

if [ "$FAIL" -eq 0 ]; then log "SELFTEST PASSED"; else log "SELFTEST FAILED"; exit 1; fi
