# proxmox-host-config

General Proxmox host OS-level settings that don't belong to any other
specific concern (storage, networking, ACME). Currently: timezone
(`Europe/Zurich`, IANA name — handles CET/CEST daylight-saving
transitions automatically, unlike a fixed "CEST" string).

Uses only `null_resource` + SSH — no `bpg/proxmox` provider/API
credentials needed, since everything here is a plain host command.

## Applying

```bash
source ~/homelab-env.sh
tofu init -backend-config="access_key=$MINIO_ROOT_USER" -backend-config="secret_key=$MINIO_ROOT_PASSWORD"
tofu plan
tofu apply
```