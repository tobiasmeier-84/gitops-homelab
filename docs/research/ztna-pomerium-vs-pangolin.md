# Research: Self-Hosted ZTNA for a Home-Lab Admin Plane — Pomerium vs. Pangolin

**Date:** August 2026
**Context:** Supporting research for ADR-0045. Full comparison
conducted via the Research feature, evaluating ZTNA tools for gating
Proxmox VE UI + SSH access (network switches, Proxmox hosts) behind
Microsoft Entra ID, for every session including from the internal
network, fronted by the existing HAProxy VRRP L4/TCP-SNI edge.

## TL;DR
- **Pomerium is the better-fit primary recommendation.** Purpose-built
  identity-aware proxy; Entra ID and "Native SSH" CA-trust features are
  fully open source (Apache 2.0) with no paywall; explicitly documents
  the exact "L4 edge in front of Pomerium" topology already in use here.
- **Pangolin is excellent software but a weaker fit for two structural
  reasons:** its architecture is a *tunneled* reverse proxy / VPN
  replacement (WireGuard-based, oriented toward exposing services
  through NAT), and — decisively — both external OIDC/SSO (Entra ID)
  and SSH are gated behind its Enterprise Edition (free for home use,
  but requires an activated license key).
- **Teleport** is a serious third option if SSH session
  recording/audit becomes a priority later.

## Comparison Table

| Dimension | Pomerium | Pangolin | Teleport (alt) |
|---|---|---|---|
| **License (core)** | Apache-2.0; Entra ID + HTTP + TCP + Native SSH all free | AGPL-3 CE; **Entra ID + SSH require EE license key** (free <$100K rev) | AGPL-3 CE + paid Enterprise |
| **Entra ID / OIDC** | Native, documented, free in Core | Dedicated integration but **EE-gated** | OIDC/SAML incl. Entra, some SSO features paid |
| **HTTP reverse proxy (clientless)** | Yes (native, Envoy L7) | Yes (Traefik) | Yes (app access) |
| **Raw TCP / SSH** | TCP tunnel (cli/desktop) **or** Native SSH CA-trust (standard client, no agent) | Browser SSH + private CLI via **Olm client**, **EE-gated** | Native SSH (agent-based), recording |
| **SSH client tooling** | None in Native SSH mode (standard `ssh`) | Olm client needed for private CLI | `tsh` client / agents |
| **Behind L4 TCP/SNI HAProxy** | **Explicitly documented & recommended** (L4 edge guide) | Awkward — it *is* the edge; WireGuard UDP bypasses HAProxy | Works; proxy expects to be edge |
| **Maturity** | Since 2019, company-backed, stable | Since Sept 2024, ~21k stars, YC S25, very active but young | Since 2016, mature |
| **Security audit** | **Cure53 (2021)** published | No public 3rd-party audit (Cloud has ISO/SOC2) | Cure53 (2017, 2018) |
| **Recent CVEs** | Authz/Envoy issues, backported patches | **Auth-bypass (9.1) + 2FA priv-esc (9.8) in 2025–26** | Periodic, actively patched |
| **Community** | Focused; forum + Discord; maintainer-driven | Large Discord (~8k), heavy tutorial ecosystem | Large, enterprise + OSS |
| **Footprint (small VM)** | 2 containers, no external DB | Server+Traefik+Gerbil+connectors+DB | Heavier (auth+proxy+node agents) |

## Key Findings

1. **Licensing is the single most decisive differentiator.** Pomerium
   Core is Apache-2.0 and self-hostable for free, with Entra ID OIDC,
   HTTP routing, TCP tunneling, and Native SSH all in the open-source
   core. Pangolin is dual-licensed (AGPL-3 Community + Fossorial
   Commercial Enterprise Edition), and external identity providers
   (Entra ID) and SSH are Enterprise-Edition features specifically.

2. **Both handle mixed HTTP + SSH, via different philosophies.**
   Pomerium: Layer-7 identity-aware reverse proxy (Envoy-based),
   clientless browser HTTPS, SSH via raw TCP tunnel or the newer Native
   SSH mode (Pomerium as an SSH CA issuing short-lived certs — works
   with standard `ssh`/`scp`/`sftp`, no client install, no server
   agent beyond `TrustedUserCAKeys`). Pangolin: clientless browser
   HTTP/SSH, raw TCP/SSH over WireGuard through Newt/Olm clients.

3. **HAProxy L4/TCP-SNI passthrough is documented as first-class for
   Pomerium specifically.** Docs explicitly state: *"Pomerium should
   not be placed behind another HTTP proxy. Instead, configure your
   load balancer in L4 or TCP mode."* Dedicated guide: "SSH over port
   443 through an L4 edge." Pangolin expects to *be* the edge
   (terminates TLS itself, needs public 80/443 + UDP 51820/21820 for
   WireGuard) — fronting it with an L4 HAProxy is less natural.

4. **Pangolin has a larger, faster-growing community; Pomerium has the
   longer production track record and a formal security audit.**
   Pangolin: Fossorial, Inc. (YC S25), first commits Sept 2024, ~20-21k
   GitHub stars, 1M+ deployments claimed, $4.7M seed (Oct 2025).
   Pomerium: running since 2019, founder Bobby DeSimone (ex-BeyondTrust),
   $13.75M Series A led by Benchmark (June 2024, $18M total raised),
   Cure53 security audit (March 2021).

5. **Both have handled CVEs; Pangolin's recent ones are more severe.**
   Pangolin: CVE-2025-56332 (auth bypass, CVSS 9.1, ≤v1.6.2, fixed
   1.7.0), CVE-2025-56333 (2FA privilege escalation, CVSS 9.8,
   published Dec 2025), CVE-2026-3209 (access-control bypass, fixed
   1.15.4-s.4). Pomerium's CVEs are mostly authz-logic or inherited-Envoy
   issues, disclosed via GitHub advisories with backported patches.

## Recommendation (adopted in ADR-0045)

Deploy Pomerium Core as the identity gate. See ADR-0045 for the full
staged rollout plan and the known caveat regarding HPE Comware SSH
compatibility with Native SSH CA-trust mode (unverified — needs direct
testing against `medina`/`anderson` before finalizing switch-access
design).

## Caveats from the original research

- Pangolin EE "free" ≠ unrestricted — requires an activated license
  key, governed by the Fossorial Commercial License.
- Native SSH CA-trust depends on target SSH server supporting
  `TrustedUserCAKeys` — confirmed for standard OpenSSH, unconfirmed for
  HPE Comware.
- Both projects move fast; re-verify current CE/EE feature splits and
  CVE status before final implementation, not just at research time.
- Whichever tool is used, subscribe to its security advisories given
  the severity of vulnerabilities found in this space recently.