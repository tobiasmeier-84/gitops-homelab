#!/usr/bin/env bash
# Collects ONE app's backup credentials into a private file for Ansible (ADR-0054).
#
#   scripts/app-backup-creds.sh <app>        e.g.  scripts/app-backup-creds.sh forscher
#
# Reads the Backblaze, OVH and Azure credentials from the OpenTofu outputs of the three
# backup-infra stacks (needs backend access like any `tofu output`, no provider credentials),
# asks for the Bitwarden machine-account token and project ID (typed, hidden, never printed),
# and writes ~/.homelab/app-backup-<app>.json with mode 600. Nothing secret goes to the
# screen, the shell history, a command line or the repository.
# Ansible (role app-backup-secrets) turns that file into the Kubernetes secret.
set -euo pipefail

APP="${1:-}"
[[ "$APP" =~ ^[a-z][a-z0-9]{1,9}$ ]] || { echo "usage: $0 <app>   (2-10 chars, lowercase letters and digits)" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required (brew install jq)" >&2; exit 2; }
command -v tofu >/dev/null || { echo "tofu is required" >&2; exit 2; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${APP_BACKUP_CREDS_DIR:-$HOME/.homelab}"
OUT="$OUT_DIR/app-backup-$APP.json"

stack_output() { # stack output-name -> the entry of this app, as JSON on stdout
  local json
  json=$(cd "$ROOT/opentofu/$1" && tofu output -json "$2") ||
    { echo "cannot read output '$2' of $1 - applied? backend credentials loaded (source ~/homelab-env.sh)?" >&2; return 1; }
  printf '%s' "$json" | jq -e --arg app "$APP" '.[$app]' ||
    { echo "output '$2' of $1 has no entry for '$APP' - is it in backup_apps and applied?" >&2; return 1; }
}

echo "Reading OpenTofu outputs (nothing is printed)..."
B2=$(stack_output backup-infra-backblaze app_backup_keys)
OVH=$(stack_output backup-infra-ovhcloud app_backup_keys)
AZ=$(stack_output backup-infra-azure app_backup_vaults)

read -r -s -p "Bitwarden access token of the '$APP' machine account (hidden): " BW_TOKEN; echo
read -r -p "Bitwarden project ID of the '$APP' project: " BW_PROJECT
if [ -z "$BW_TOKEN" ] || [ -z "$BW_PROJECT" ]; then echo "token and project ID must not be empty" >&2; exit 1; fi

umask 077
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
TMP=$(mktemp "$OUT_DIR/.app-backup-$APP.XXXXXX")
trap 'rm -f "$TMP"' EXIT

# The secrets travel through stdin only, never through arguments (visible in `ps`).
{
  printf '%s\n' "$B2" "$OVH" "$AZ"
  printf '%s' "$BW_TOKEN" | jq -Rs '{bw_token: .}'
  printf '%s' "$BW_PROJECT" | jq -Rs '{bw_project: (. | gsub("\\s"; ""))}'
} | jq -s '
  {
    OVH_S3_ACCESS_KEY:   .[1].access_key,
    OVH_S3_SECRET_KEY:   .[1].secret_key,
    B2_KEY_ID:           .[0].key_id,
    B2_KEY_SECRET:       .[0].key_secret,
    AZURE_TENANT_ID:     .[2].tenant_id,
    AZURE_CLIENT_ID:     .[2].client_id,
    AZURE_CLIENT_SECRET: .[2].client_secret,
    KV_URL:              .[2].vault_url,
    BW_ACCESS_TOKEN:     .[3].bw_token,
    BW_PROJECT_ID:       .[4].bw_project
  }' >"$TMP"

# Every field must exist and be non-empty.
jq -e 'to_entries | all(.value != null and .value != "")' "$TMP" >/dev/null ||
  { echo "a credential is missing or empty - nothing was written" >&2; exit 1; }

mv "$TMP" "$OUT"
trap - EXIT
echo "Wrote $OUT (mode 600) with fields: $(jq -r 'keys | join(", ")' "$OUT")"
echo "Next: cd ansible && ansible-playbook site.yml --tags app_backup --limit rke2_nodes --check"
