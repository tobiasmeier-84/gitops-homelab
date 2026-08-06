# OpenTofu

Provisions the Proxmox VMs for the RKE2 cluster (`environments/prod/`), using the reusable `modules/proxmox-vm/` module. Uses the `bpg/proxmox` provider.

State is not committed to this repo — see `.gitignore`. Remote state is hosted on a self-hosted MinIO instance, bootstrapped separately (local state, minimal footprint) before the main OpenTofu configuration runs against it — see ADR-0024 and the bootstrap-ordering runbook (ADR-0025, `docs/runbooks/`).

## TLS via certbot + Cloudflare DNS-01 (ADR-0038)

MinIO has no built-in ACME client (unlike Proxmox, see ADR-0037), so
`certbot` handles issuance/renewal. Provisioned automatically by
`null_resource.minio_tls_setup` in `main.tf`.

### Prerequisites

A dedicated Cloudflare API token (separate from the Proxmox one) —
**Zone:DNS:Edit** + **Zone:Zone:Read**, scoped to `solsys.dev` only:

​```bash
sops secrets/minio-cloudflare-token.enc.yaml
​```
​```yaml
cloudflare_api_token: "<token>"
​```

### How it works

- Cert obtained via `certbot certonly --dns-cloudflare`, for
  `iapetus.orbit.solsys.dev`.
- Placed at `/etc/minio/certs/public.crt` and `private.key` — **not**
  MinIO's default `$HOME/.minio/certs`, since `minio-user` has no home
  directory. `MINIO_OPTS` in `/etc/default/minio` explicitly sets
  `--certs-dir /etc/minio/certs`.
- Renewal: Debian's `certbot` package installs its own systemd timer
  automatically (runs twice daily). A deploy-hook
  (`/etc/letsencrypt/renewal-hooks/deploy/minio-reload.sh`) copies the
  renewed cert into place on renewal; MinIO auto-detects the file change
  and reloads without needing a restart.

### Verifying

​```bash
ssh admin@iapetus.orbit.solsys.dev "sudo ls -la /etc/minio/certs/"
ssh admin@iapetus.orbit.solsys.dev "sudo systemctl status minio"
curl -v https://iapetus.orbit.solsys.dev:9000/minio/health/live 2>&1 | grep -i "subject:\|SSL certificate"
ssh admin@iapetus.orbit.solsys.dev "sudo systemctl list-timers | grep certbot"
​```

### Note on internal traffic

The state-backup script's own `mc`/`rclone` calls use `http://localhost:9000`
— left on HTTP since this traffic never leaves the VM. Not fully
consistent with the external HTTPS endpoint, but a reasonable trade-off;
revisit if end-to-end TLS is ever a hard requirement.
