# ADR-0038: MinIO TLS via certbot + Cloudflare DNS-01

**Status:** Accepted

## Context
`iapetus`/MinIO served plain HTTP by default — no encryption in transit for OpenTofu state traffic or backup uploads/downloads. Unlike Proxmox (ADR-0037), MinIO has no built-in ACME client, so a certificate needs to be obtained and kept renewed by a separate mechanism.

## Decision
`certbot` with the Cloudflare DNS-01 plugin, run via OpenTofu provisioning (`null_resource.minio_tls_setup` in `opentofu/bootstrap-minio/main.tf`) rather than a manual one-off setup — consistent with the state-backup precedent of keeping host-level configuration in git rather than only living on the VM.

- Certificate placed at `/etc/minio/certs/` (`public.crt`/`private.key`), with `--certs-dir` explicitly set in `MINIO_OPTS`, since `minio-user` (the systemd service's user) has no home directory for MinIO's default `$HOME/.minio/certs` lookup.
- Renewal relies on Debian's own `certbot` systemd timer (installed automatically with the package, runs twice daily) plus a deploy-hook script that copies the renewed cert into MinIO's cert directory — MinIO auto-detects file changes and reloads without a restart.
- A separate, dedicated Cloudflare API token from the one used for Proxmox's ACME setup, consistent with this project's credential-separation pattern throughout.

## Reasoning
Doing this by hand (as initially attempted) would mean the entire TLS setup silently disappears on any future rebuild of `iapetus` — exactly the class of gap this project has been actively closing everywhere else. Provisioning it via OpenTofu keeps it reconstructable from git alongside everything else on this VM.

## Consequences
- OpenTofu's `s3` backend endpoint (used by `bootstrap-storage` and future configs) updated from `http://` to `https://iapetus.orbit.solsys.dev:9000`.
- Internal, same-VM traffic (the state-backup script's own `mc`/`rclone` calls, which use `localhost`) was left on HTTP — reasonable given it never leaves the VM, though noted as an inconsistency if full end-to-end TLS is ever desired.
- A related, incidental fix made during this work: `opentofu/bootstrap-minio/main.tf`'s Debian cloud image download was pinned to a specific dated snapshot URL instead of tracking `latest`, after an unexpected image-size mismatch surfaced mid-session. Prevents a future `tofu apply` from silently picking up a different base image than what's actually running.