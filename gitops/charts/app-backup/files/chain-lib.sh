#!/bin/sh
# Shared by backup.sh and selftest.sh (sourced, never run directly). ADR-0054.
#
# Same storage layout and restore recipe as the Nextcloud backup (ADR-0005), per backup NAME:
#   NAME/0001 NAME/0002 ...   encrypted data in CHUNK_MIB-sized chunks
#   NAME/MANIFEST             written LAST - a backup exists only if its MANIFEST exists
# NAME is "<app>-<YYYYMMDD>-<HHMMSS>" in UTC, so its age can be read from the name alone.
#
# Differences to the Nextcloud library, on purpose:
#   * retention is by AGE (chain_prune_age): anything older than MAX_AGE_DAYS is deleted with its
#     key, in both chains, no matter whether the latest backup succeeded (privacy limit wins)
#   * every list call carries the app prefix (the per-app credentials only reach that prefix)
#   * bucket names, endpoints and the vault URL come from the environment, not from the code
#
# Note: functions called from an `if` run with `set -e` disabled, so every step checks its own result.

: "${APP_NAME:?APP_NAME is required}"
: "${BUCKET_A:?}" "${BUCKET_B:?}" "${EP_A:?}" "${EP_B:?}"
MAX_AGE_DAYS="${MAX_AGE_DAYS:-13}"
CHUNK_MIB="${CHUNK_MIB:-512}"
NAME_RE="^${APP_NAME}-[0-9]{8}-[0-9]{6}$"

# Tools live in an alternate root installed at start (see tools_setup); overridable for tests.
AWS="${AWS:-/tmp/pkgroot/usr/bin/aws}"
AWS_PY="${AWS_PY:-/tmp/pkgroot/usr/bin/python3}"
AGE="${AGE:-/tmp/pkgroot/usr/bin/age}"
AGE_KEYGEN="${AGE_KEYGEN:-/tmp/pkgroot/usr/bin/age-keygen}"
ZSTD="${ZSTD:-/tmp/pkgroot/usr/bin/zstd}"
UNZIP="${UNZIP:-/tmp/pkgroot/usr/bin/unzip}"
CURL="${CURL:-/tmp/pkgroot/usr/bin/curl}"
JQ="${JQ:-/tmp/pkgroot/usr/bin/jq}"
export LD_LIBRARY_PATH="/tmp/pkgroot/usr/lib:/tmp/pkgroot/lib:${LD_LIBRARY_PATH:-}"
export HOME=/tmp   # bws and aws want a writable home

BWS_URL="https://github.com/bitwarden/sdk-sm/releases/download/bws-v2.1.0/bws-x86_64-unknown-linux-musl-2.1.0.zip"
BWS_ZIP_SHA256="f59ee150e42b82128d437087e9bac920053c6bfddcb960d20ce9386e5ac9bba6"

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"; }

tools_setup() {
  [ "${SKIP_TOOL_INSTALL:-}" = "1" ] && return 0
  log "Installing age, zstd, aws-cli, unzip, curl, jq into an alternate root..."
  mkdir -p /tmp/pkgroot
  apk add --no-cache --root /tmp/pkgroot --initdb --repositories-file /etc/apk/repositories --allow-untrusted \
    age zstd aws-cli unzip curl jq ||
    echo "apk had non-fatal post-install trigger errors (expected under non-root), continuing"
}

# TLS: verify certificates (no curl -k). Prefer the bundle from the alternate root.
CA_BUNDLE="/tmp/pkgroot/etc/ssl/certs/ca-certificates.crt"
[ -s "$CA_BUNDLE" ] || CA_BUNDLE="/etc/ssl/certs/ca-certificates.crt"
curl_ca() { "$CURL" --cacert "$CA_BUNDLE" -sS --retry 3 --retry-delay 2 "$@"; }

aws_tune() {
  "$AWS_PY" "$AWS" configure set default.s3.multipart_chunksize 64MB
  "$AWS_PY" "$AWS" configure set default.s3.max_concurrent_requests 4
  if [ "${UPLOAD_MAX_BANDWIDTH_KBPS:-0}" -gt 0 ]; then
    "$AWS_PY" "$AWS" configure set default.s3.max_bandwidth "${UPLOAD_MAX_BANDWIDTH_KBPS}KB/s"
    log "Upload bandwidth capped at ${UPLOAD_MAX_BANDWIDTH_KBPS} KB/s"
  fi
}

# ---------------------------------------------------------------- generic S3 helpers
s3_head_len() { # bucket endpoint key -> prints ContentLength
  "$AWS_PY" "$AWS" s3api head-object --bucket "$1" --key "$3" --endpoint-url "$2" --query ContentLength --output text
}

abort_mpu() { # bucket endpoint key_prefix (best effort: abort dangling multipart uploads)
  "$AWS_PY" "$AWS" s3api list-multipart-uploads --bucket "$1" --endpoint-url "$2" --prefix "$3" \
    --query 'Uploads[].[Key,UploadId]' --output text 2>/dev/null | while read -r _k _u; do
    if [ -n "$_u" ] && [ "$_u" != "None" ]; then
      "$AWS_PY" "$AWS" s3api abort-multipart-upload --bucket "$1" --key "$_k" --upload-id "$_u" --endpoint-url "$2" || true
    fi
  done
  return 0
}

# ---------------------------------------------------------------- Azure Key Vault (Chain A keys)
az_token() {
  curl_ca -X POST "https://login.microsoftonline.com/${AZURE_TENANT_ID}/oauth2/v2.0/token" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "client_id=${AZURE_CLIENT_ID}" \
    --data-urlencode "client_secret=${AZURE_CLIENT_SECRET}" \
    --data-urlencode "scope=https://vault.azure.net/.default" \
    -o /tmp/az-token.json || { log "Azure: token request failed (network/TLS)" >&2; return 1; }
  _t=$("$JQ" -r '.access_token // empty' /tmp/az-token.json)
  if [ -z "$_t" ]; then
    log "Azure: no access token: $("$JQ" -r '.error_description // .error // "unknown"' /tmp/az-token.json | head -c 300)" >&2
    rm -f /tmp/az-token.json
    return 1
  fi
  rm -f /tmp/az-token.json
  printf '%s' "$_t"
}

az_put_secret() { # name value
  _tok=$(az_token) || return 1
  # JSON is built by jq: the age key file contains newlines and must be escaped properly.
  "$JQ" -n --arg v "$2" '{value:$v}' >/tmp/az-body.json || return 1
  _code=$(curl_ca -o /tmp/az-resp.json -w '%{http_code}' -X PUT "${KV_URL}/secrets/$1?api-version=7.4" \
    -H "Authorization: Bearer ${_tok}" -H "Content-Type: application/json" -d @/tmp/az-body.json) || _code="000"
  rm -f /tmp/az-body.json
  log "Azure Key Vault store ($1): HTTP ${_code}"
  case "$_code" in
    2??) return 0 ;;
    *) log "  response: $(head -c 400 /tmp/az-resp.json 2>/dev/null)"; return 1 ;;
  esac
}

az_get_secret() { # name -> prints value
  _tok=$(az_token) || return 1
  curl_ca -X GET "${KV_URL}/secrets/$1?api-version=7.4" -H "Authorization: Bearer ${_tok}" -o /tmp/az-get.json || return 1
  "$JQ" -r '.value // empty' /tmp/az-get.json
}

az_delete_secret() { # name (delete AND purge: soft-deleted secrets would live on)
  _tok=$(az_token) || { log "  WARNING: Azure token failed, secret $1 NOT deleted"; return 1; }
  _c1=$(curl_ca -o /dev/null -w '%{http_code}' -X DELETE "${KV_URL}/secrets/$1?api-version=7.4" -H "Authorization: Bearer ${_tok}") || _c1=000
  sleep 2
  _c2=$(curl_ca -o /dev/null -w '%{http_code}' -X DELETE "${KV_URL}/deletedsecrets/$1?api-version=7.4" -H "Authorization: Bearer ${_tok}") || _c2=000
  log "  Azure secret $1: delete HTTP ${_c1}, purge HTTP ${_c2}"
  case "$_c1" in 2??|404) ;; *) return 1 ;; esac
  case "$_c2" in 2??|404) ;; *) return 1 ;; esac
}

az_list_secret_names() { # -> names, one per line (this vault holds only this app's keys)
  _tok=$(az_token) || return 1
  _url="${KV_URL}/secrets?api-version=7.4"
  while [ -n "$_url" ]; do
    curl_ca -X GET "$_url" -H "Authorization: Bearer ${_tok}" -o /tmp/az-list.json || return 1
    "$JQ" -r '.value[]?.id | split("/") | last' /tmp/az-list.json
    _url=$("$JQ" -r '.nextLink // empty' /tmp/az-list.json)
  done
}

# ---------------------------------------------------------------- Bitwarden Secrets Manager (Chain B keys)
bws_init() {
  export BWS_SERVER_URL="https://vault.bitwarden.eu"
  export BWS_ACCESS_TOKEN="$BW_ACCESS_TOKEN"
  [ -x /tmp/bws ] && return 0
  curl_ca -L "$BWS_URL" -o /tmp/bws.zip || { log "bws: download failed"; return 1; }
  echo "$BWS_ZIP_SHA256  /tmp/bws.zip" | sha256sum -c - >/dev/null || { log "bws: CHECKSUM MISMATCH - refusing to run a binary that does not match the pinned hash"; return 1; }
  "$UNZIP" -o /tmp/bws.zip -d /tmp >/dev/null || return 1
  chmod +x /tmp/bws
}

bws_put_secret() { # name value
  /tmp/bws secret create "$1" "$2" "$BW_PROJECT_ID" >/dev/null || { log "Bitwarden: secret create FAILED ($1)"; return 1; }
  _id=$(/tmp/bws secret list "$BW_PROJECT_ID" | "$JQ" -r --arg k "$1" '.[] | select(.key==$k) | .id') || _id=""
  [ -n "$_id" ] || { log "Bitwarden: secret $1 not found after create"; return 1; }
  log "Bitwarden secret stored ($1): $_id"
}

bws_get_secret() { # name -> prints value
  /tmp/bws secret list "$BW_PROJECT_ID" | "$JQ" -r --arg k "$1" '.[] | select(.key==$k) | .value'
}

bws_delete_secret() { # name
  _id=$(/tmp/bws secret list "$BW_PROJECT_ID" | "$JQ" -r --arg k "$1" '.[] | select(.key==$k) | .id') || _id=""
  if [ -n "$_id" ]; then
    /tmp/bws secret delete "$_id" >/dev/null && log "  deleted Bitwarden secret $_id"
  else
    log "  no Bitwarden secret named $1 (nothing to delete)"
  fi
}

bws_list_secret_names() {
  /tmp/bws secret list "$BW_PROJECT_ID" | "$JQ" -r '.[].key'
}

# Versioned bucket (B2): delete every version and every delete marker under one key or prefix.
b2_purge_key() { # key_or_prefix
  for _kind in Versions DeleteMarkers; do
    "$AWS_PY" "$AWS" s3api list-object-versions --bucket "$BUCKET_B" --prefix "$1" --endpoint-url "$EP_B" \
      --query "{Objects: ${_kind}[].{Key:Key,VersionId:VersionId}}" --output json >/tmp/del.json || continue
    if [ "$("$JQ" '(.Objects // []) | length' /tmp/del.json)" -gt 0 ]; then
      "$AWS_PY" "$AWS" s3api delete-objects --bucket "$BUCKET_B" --endpoint-url "$EP_B" --delete file:///tmp/del.json >/dev/null
    fi
  done
}

# ---------------------------------------------------------------- chains A and B behind one interface
chain_a_env() { export AWS_ACCESS_KEY_ID="$OVH_S3_ACCESS_KEY"; export AWS_SECRET_ACCESS_KEY="$OVH_S3_SECRET_KEY"; }
chain_b_env() { export AWS_ACCESS_KEY_ID="$B2_KEY_ID"; export AWS_SECRET_ACCESS_KEY="$B2_KEY_SECRET"; }

# Selects chain A|B: exports its credentials and sets C_BUCKET / C_EP.
chain_setup() {
  case "$1" in
    A) chain_a_env; C_BUCKET="$BUCKET_A"; C_EP="$EP_A" ;;
    B) chain_b_env; bws_init || return 1; C_BUCKET="$BUCKET_B"; C_EP="$EP_B" ;;
    *) return 1 ;;
  esac
}

key_put() { case "$1" in A) az_put_secret "$2" "$3" ;; B) bws_put_secret "$2" "$3" ;; *) return 1 ;; esac; }
key_get() { case "$1" in A) az_get_secret "$2" ;; B) bws_get_secret "$2" ;; *) return 1 ;; esac; }
key_del() { case "$1" in A) az_delete_secret "$2" ;; B) bws_delete_secret "$2" ;; *) return 1 ;; esac; }
key_names() { case "$1" in A) az_list_secret_names ;; B) bws_list_secret_names ;; *) return 1 ;; esac; }

chain_has_key() { # A|B object_key
  chain_setup "$1" || return 1
  "$AWS_PY" "$AWS" s3api head-object --bucket "$C_BUCKET" --key "$2" --endpoint-url "$C_EP" >/dev/null 2>&1
}

# Names of this app's backups in the bucket (complete or not). Returns 1 if the listing fails.
chain_list_names() { # A|B
  chain_setup "$1" || return 1
  _out=$("$AWS_PY" "$AWS" s3api list-objects-v2 --bucket "$C_BUCKET" --prefix "${APP_NAME}-" --delimiter "/" --endpoint-url "$C_EP" \
    --query 'CommonPrefixes[].Prefix' --output json) || { log "Chain $1: listing the bucket failed"; return 1; }
  printf '%s' "$_out" | "$JQ" -r '.[]? | select(. != null)' | sed -e 's#/$##' | grep -E "$NAME_RE" || true
}

chain_is_complete() { chain_has_key "$1" "$2/MANIFEST"; }

# True while anything of this backup (any version, any chunk) is still in the bucket.
chain_has_leftovers() { # A|B name
  chain_setup "$1" || return 1
  _hn=$("$AWS_PY" "$AWS" s3api list-objects-v2 --bucket "$C_BUCKET" --prefix "$2/" --endpoint-url "$C_EP" \
    --query 'length(Contents[])' --output text 2>/dev/null) || return 1
  [ -n "$_hn" ] && [ "$_hn" != "None" ] && [ "$_hn" != "0" ]
}

# Removes all data of one backup (not its key).
chain_remove_backup() { # A|B name
  chain_setup "$1" || return 1
  abort_mpu "$C_BUCKET" "$C_EP" "$2"
  case "$1" in
    A) "$AWS_PY" "$AWS" s3 rm "s3://$C_BUCKET/$2/" --recursive --endpoint-url "$C_EP" >/dev/null 2>&1 || true ;;
    B) b2_purge_key "$2/" >/dev/null 2>&1 || true ;;
  esac
  if chain_has_leftovers "$1" "$2"; then
    log "  WARNING: objects of $2 are still listed in chain $1 after the delete"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- age arithmetic (pure sh, UTC)
_num() { _nx=$(printf '%s' "$1" | sed 's/^0*//'); echo "${_nx:-0}"; } # strip leading zeros (08 is not octal)

days_from_civil() { # year month day -> days since 1970-01-01
  _y=$(_num "$1"); _m=$(_num "$2"); _d=$(_num "$3")
  if [ "$_m" -le 2 ]; then _y=$((_y - 1)); fi
  _era=$((_y / 400))
  _yoe=$((_y - _era * 400))
  _mp=$(((_m + 9) % 12))
  _doy=$(((153 * _mp + 2) / 5 + _d - 1))
  _doe=$((_yoe * 365 + _yoe / 4 - _yoe / 100 + _doy))
  echo $((_era * 146097 + _doe - 719468))
}

epoch_from_name() { # <app>-YYYYMMDD-HHMMSS -> epoch seconds (UTC)
  _s=${1#"${APP_NAME}"-}
  _dt=${_s%-*}; _tm=${_s#*-}
  _days=$(days_from_civil "$(printf '%s' "$_dt" | cut -c1-4)" "$(printf '%s' "$_dt" | cut -c5-6)" "$(printf '%s' "$_dt" | cut -c7-8)")
  echo $((_days * 86400 + $(_num "$(printf '%s' "$_tm" | cut -c1-2)") * 3600 + $(_num "$(printf '%s' "$_tm" | cut -c3-4)") * 60 + $(_num "$(printf '%s' "$_tm" | cut -c5-6)")))
}

# ---------------------------------------------------------------- retention by AGE
# Deletes, in BOTH chains, every backup (data and key) that is MAX_AGE_DAYS or older, and every
# incomplete leftover older than a day. Never touches CURRENT_NAME (the run in progress).
# Runs regardless of whether the latest backup worked: the privacy limit is not negotiable.
# Returns 1 if anything that should be gone could not be deleted.
chain_prune_age() { # A|B
  chain_setup "$1" || { log "Prune chain $1: setup failed"; return 1; }
  _pnow=$(date -u +%s)
  _pbad=0
  _pbn=$(chain_list_names "$1") || { log "Prune chain $1: cannot list the bucket"; _pbad=1; _pbn=""; }
  _pkn=$(key_names "$1") || { log "Prune chain $1: cannot list the vault"; _pbad=1; _pkn=""; }
  _pnames=$(printf '%s\n%s\n' "$_pbn" "$(printf '%s\n' "$_pkn" | grep -E "$NAME_RE" || true)" | grep . | sort -u || true)
  log "Pruning chain $1 by age (maximum $MAX_AGE_DAYS days); known backups/keys: $(printf '%s\n' "$_pnames" | grep -c . || true)"
  for _pn in $_pnames; do
    [ "$_pn" = "${CURRENT_NAME:-}" ] && continue
    _pas=$((_pnow - $(epoch_from_name "$_pn")))
    _pad=$((_pas / 86400))
    _pdrop=""
    if [ "$_pad" -ge "$MAX_AGE_DAYS" ]; then
      _pdrop="older than the limit (${_pad} days)"
    elif [ "$_pad" -ge 1 ] && ! chain_is_complete "$1" "$_pn"; then
      _pdrop="incomplete leftover (${_pad} days)"
    fi
    [ -n "$_pdrop" ] || continue
    log "  deleting $_pn: $_pdrop"
    chain_remove_backup "$1" "$_pn" || _pbad=1
    key_del "$1" "$_pn" || _pbad=1
  done
  return $_pbad
}

# ---------------------------------------------------------------- chunked upload
# Uploads <dir>/data.age to one chain in CHUNK_MIB chunks, verifies each chunk's size, writes the
# MANIFEST last. Returns 0 = complete, 1 = failed. The backup is small; no resume logic needed.
upload_chain() { # A|B dir name
  _x="$1"; _dir="$2"; _name="$3"
  chain_setup "$_x" || { log "Chain $_x: setup failed"; return 1; }
  _size=$(stat -c%s "$_dir/data.age")
  _cb=$((CHUNK_MIB * 1048576))
  _n=$(((_size + _cb - 1) / _cb))
  log "Chain $_x: $_name - $_size bytes in $_n chunk(s) of $CHUNK_MIB MiB"
  _i=1
  while [ "$_i" -le "$_n" ]; do
    _id=$(printf '%04d' "$_i")
    _want=$_cb
    _rem=$((_size - (_i - 1) * _cb))
    [ "$_rem" -lt "$_want" ] && _want=$_rem
    _tmp="$_dir/chunk.tmp"
    rm -f "$_tmp"
    dd if="$_dir/data.age" of="$_tmp" bs=1M skip=$(((_i - 1) * CHUNK_MIB)) count="$CHUNK_MIB" 2>/dev/null
    if [ "$(stat -c%s "$_tmp")" != "$_want" ]; then
      log "Chain $_x: chunk $_id has the wrong local size (expected $_want)"; rm -f "$_tmp"; return 1
    fi
    _ok=no; _try=1
    while [ "$_try" -le 3 ] && [ "$_ok" = no ]; do
      log "Chain $_x: uploading chunk $_id/$_n ($_want bytes), attempt $_try"
      if "$AWS_PY" "$AWS" s3 cp "$_tmp" "s3://$C_BUCKET/$_name/$_id" --endpoint-url "$C_EP" --only-show-errors; then
        _len=$(s3_head_len "$C_BUCKET" "$C_EP" "$_name/$_id") || _len=""
        if [ "$_len" = "$_want" ]; then _ok=yes; else log "Chain $_x: chunk $_id size mismatch (remote '$_len', expected $_want)"; fi
      else
        log "Chain $_x: chunk $_id upload attempt $_try failed"
      fi
      if [ "$_ok" = no ]; then abort_mpu "$C_BUCKET" "$C_EP" "$_name/$_id"; _try=$((_try + 1)); sleep 10; fi
    done
    rm -f "$_tmp"
    [ "$_ok" = yes ] || { log "Chain $_x: chunk $_id FAILED after 3 attempts"; return 1; }
    _i=$((_i + 1))
  done
  _mf="$_dir/MANIFEST.$_x"
  {
    echo "name=$_name"
    echo "size=$_size"
    echo "chunk_bytes=$_cb"
    echo "chunks=$_n"
    echo "sha256=$(sha256sum "$_dir/data.age" | awk '{print $1}')"
    echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "data_as_of=${DATA_AS_OF:-unknown}"
  } >"$_mf"
  "$AWS_PY" "$AWS" s3 cp "$_mf" "s3://$C_BUCKET/$_name/MANIFEST" --endpoint-url "$C_EP" --only-show-errors || { log "Chain $_x: MANIFEST upload FAILED"; return 1; }
  _len=$(s3_head_len "$C_BUCKET" "$C_EP" "$_name/MANIFEST") || _len=""
  [ "$_len" = "$(stat -c%s "$_mf")" ] || { log "Chain $_x: MANIFEST size mismatch"; return 1; }
  log "Chain $_x: OK - $_name complete ($_n chunk(s) + MANIFEST, key in the vault)"
}

# ---------------------------------------------------------------- restore (also used by the selftest)
chain_fetch() { # A|B name outfile   (download all chunks, decrypt with the key from the vault)
  chain_setup "$1" || return 1
  _k=$(key_get "$1" "$2") || return 1
  [ -n "$_k" ] || { log "no key for $2 in the vault"; return 1; }
  _kf="/tmp/restore-$1.key"
  printf '%s\n' "$_k" >"$_kf"
  _want=$("$AWS_PY" "$AWS" s3 cp "s3://$C_BUCKET/$2/MANIFEST" - --endpoint-url "$C_EP" --only-show-errors | sed -n 's/^chunks=//p') || _want=""
  _list=$("$AWS_PY" "$AWS" s3api list-objects-v2 --bucket "$C_BUCKET" --prefix "$2/" --endpoint-url "$C_EP" --query 'Contents[].Key' --output json |
    "$JQ" -r '.[]?' | grep -E '/[0-9]{4}$' | sort) || _list=""
  if [ -z "$_want" ] || [ "$(echo "$_list" | wc -l)" != "$_want" ]; then
    log "chunk count mismatch: manifest says '$_want', bucket has $(echo "$_list" | wc -l)"; rm -f "$_kf"; return 1
  fi
  ( for _c in $_list; do "$AWS_PY" "$AWS" s3 cp "s3://$C_BUCKET/$_c" - --endpoint-url "$C_EP" --only-show-errors || exit 1; done ) |
    "$AGE" -d -i "$_kf" >"$3" || { rm -f "$_kf"; return 1; }
  rm -f "$_kf"
}
