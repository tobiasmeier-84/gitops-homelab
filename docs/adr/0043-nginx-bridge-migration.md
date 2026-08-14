# ADR-0043: nginx SNI-passthrough bridge during platform migration

**Status:** Accepted

## Context
The new platform (RKE2 + Traefik + HAProxy VRRP) needed to be tested
against real public traffic and a real, trusted certificate before
committing to a full cutover — but the existing production reverse proxy
(`reverse`, a pre-existing bare-metal nginx host, not part of the
gitops-homelab build) already terminates TLS for genuinely live sites
(`nextcloud.topadata.ch`, `plex.topadata.ch`, `transmission.topadata.ch`)
that couldn't be disrupted during testing.

## Decision
Use nginx's `stream` module with `ssl_preread` to route incoming HTTPS
connections by SNI hostname **without decrypting them** — genuinely new
hostnames (`agatha-king.gate.solsys.dev`, `argocd.app.solsys.dev`) pass
straight through, undecrypted, to the new stack's HAProxy VRRP floating
IP (`10.10.40.10:443`); everything else falls through to the existing
sites, which continue terminating TLS exactly as before, just now bound
to `127.0.0.1:8443` instead of the public interface directly.

```nginx
stream {
    map $ssl_preread_server_name $backend {
        agatha-king.gate.solsys.dev  new_stack;
        argocd.app.solsys.dev        new_stack;
        default                      old_stack;
    }

    upstream new_stack {
        server 10.10.40.10:443;
    }

    upstream old_stack {
        server 127.0.0.1:8443;
    }

    server {
        listen 443;
        proxy_pass $backend;
        ssl_preread on;
    }
}
```

Files changed on `reverse`: `/etc/nginx/nginx.conf` (added the `stream`
block — a top-level context, sibling to `http {}`, not nested inside
it), `/etc/nginx/sites-available/nextcloud` and
`/etc/nginx/conf.d/plex.conf` (`listen 443 ssl` → `listen
127.0.0.1:8443 ssl` on the 3 existing TLS-terminating server blocks —
plain `:80` redirect blocks untouched, since `stream` only concerns
port 443).

Along the way, three stale site configs from an earlier, already-deleted
cluster attempt were found and removed from `sites-enabled/`
(`argocd.topadata.ch`, `pve.topadata.ch`, `app.topadata.ch` — all
plain-HTTP-only, never actually conflicted with anything, just unused
cruft).

## Reasoning
- **The real certificate stays owned entirely by cert-manager/Traefik.**
  `ssl_preread` reads only the unencrypted SNI field from the TLS
  ClientHello — the actual handshake, and the certificate served, both
  happen at the new stack. No double-termination, no second certificate
  needed at nginx for the new hostnames.
- **Zero disruption to existing production sites.** The `default
  old_stack` fallback means any hostname not explicitly added keeps
  working exactly as before — an additive change, not a rewrite.
- **This is the actual mechanism for the eventual full cutover too**,
  not just a temporary testing hack — cutover becomes "migrate more
  hostnames into the `new_stack` branch over time," using the identical
  pattern, until `old_stack` is empty and nginx itself can be retired
  (or repurposed) once the RV320's NAT rule points directly at the
  HAProxy floating IP.

## Consequences
- `reverse` is not part of the gitops-homelab naming scheme or IaC —
  it's pre-existing, external infrastructure, deliberately not brought
  under Expanse theming since it's explicitly transitional.
- Adding a new app's public hostname now requires one line in this
  `map` block on `reverse`, in addition to the DNS record and the app's
  own Ingress — worth remembering as a manual step until the full
  cutover retires this bridge entirely.