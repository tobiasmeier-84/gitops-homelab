# medina (MikroTik RB5009UG+S+IN) — bootstrap notes

Operational notes for bootstrapping and troubleshooting this device.
See `docs/adr/0051-mikrotik-router-replacement.md` for the architecture
decisions and full target-state design.

# medina (MikroTik RB5009UG+S+IN) — bootstrap notes

Operational notes for bootstrapping and troubleshooting this device.
See `docs/adr/0051-mikrotik-router-replacement.md` for the architecture
decisions and full target-state design.

## Current status

**Feature-complete relative to the RV320, fully IaC-managed, tested in
isolation on `192.168.11.0/24`. WAN not yet connected; physical
migration not yet performed.**

Built and verified via `tofu apply`, in order:
- Bridge (`bridge-lan`, VLAN-filtering enabled) + all 8 physical ports
  as members
- VLAN 1 (`192.168.11.0/24`) — **active**, currently serving management
  access during testing
- VLAN 60 (old servers: kvm001-G2, kvm001, plexi, reversi, cloudi, nfs)
  — defined, `192.168.101.1/24`, **deliberately no port assigned**,
  inert until migration
- VLANs 10/20/30/40/50 (MGMT/CLUSTER/STORAGE/DMZ-INGRESS/EGRESS) —
  defined with correct addressing, **deliberately no ports assigned**,
  inert until migration
- Forward-chain firewall: 13 explicit-allow rules (translated from the
  RV320's 14, DNS split into separate TCP/UDP rules) + explicit default
  deny, verified correctly ordered via `place_before`
- NAT: all 4 port forwards (80/443→reverse, 32400→plexi,
  2222→Deimos/Pomerium SSH)
- WireGuard: interface + 2 peers (Mac, iPhone), narrow `input`-chain
  exception for the WireGuard UDP port only, correctly positioned
  before the default `input` drop rule
- DNS: `vpn.mcrn.solsys.dev` → `dynamic.solsys.dev`, for the WireGuard
  endpoint once WAN is live

**Explicitly deferred, not forgotten:**
- **`input`-chain rework** for router-management access itself — the
  operator's stated goal is MGMT-VLAN-only access, ultimately routed
  entirely through Pomerium/Deimos rather than direct router access at
  all, consistent with this project's ZTNA philosophy. The existing
  RouterOS default `input` rules (LAN-list-based accept) remain
  completely untouched and are what's kept this whole bootstrap process
  reachable — do not remove or replace them until the Pomerium-only
  access path is actually built and proven.
- **Physical migration** — assigning real ports to VLANs 10/20/30/40/50
  and (when ready) 60, moving cables, actual cutover from the RV320.
  WAN (`ether1`) has never been connected to this router during
  bootstrap; all testing has been via `ether3` on the isolated
  `192.168.11.0/24` bootstrap network.
- **DNS role reconsideration** (Titania/Oberon vs. router) — explicitly
  deferred until the router itself is proven stable in production.

## Factory reset procedure

One low-quality third-party source found during research gave an
incorrect procedure ("power on, then hold 10 seconds") — disregard it.
Confirmed-correct procedure for the RB5009UG+S+IN, verified against
official MikroTik documentation:

1. Unplug power completely
2. Press and hold the reset button **first**, then apply power while
   still holding it (must be held before/during power-on, not after)
3. Release the button the moment the green LED starts flashing —
   triggers reset to factory defaults
4. Do not hold past ~20 seconds / until the LED goes dark — that
   triggers a different function (Netinstall server search)

Post-reset: router returns to `192.168.88.1` on the default `bridge`,
reachable via any LAN port.

## Bootstrap CLI (manual, pre-OpenTofu)

Deliberately minimal — only `ether3` touched, every other port left on
the original default bridge as a safety net during testing.

/interface bridge add name=bridge-lan vlan-filtering=yes
/interface bridge port remove [find interface=ether3]
/interface bridge port add bridge=bridge-lan interface=ether3
/interface bridge vlan add bridge=bridge-lan vlan-ids=1 untagged=ether3
/interface vlan add interface=bridge-lan name=vlan1-clients vlan-id=1
/ip address add address=192.168.11.1/24 interface=vlan1-clients


**Certificates + REST API** (needed for OpenTofu; does not survive a
factory reset, must be redone after any reset):

/certificate
add name=root-cert common-name=root-cert key-usage=key-cert-sign,crl-sign
add name=https-cert common-name=https-cert
sign root-cert
sign https-cert ca=root-cert
/ip service set www-ssl certificate=https-cert disabled=no


Verify signing actually completed — `https-cert` must show the `K`
(private key) flag in `/certificate print`. One attempt during
bootstrap appeared to run without error but left `https-cert` unsigned
— re-running `sign` a second time resolved it. Cause not fully
diagnosed; always re-check flags, don't just check for a command error.

## Known gotchas

### 1. Interface-list firewall membership must be explicit per-VLAN-interface, not just per-bridge

Factory-default RouterOS ships with `chain=input action=drop
in-interface-list=!LAN`, dropping management traffic not arriving from
an interface in the `LAN` list. Adding the **bridge** to that list is
**not sufficient** for a **VLAN sub-interface** built on top of it —
RouterOS evaluates the firewall against the actual Layer-3 interface
traffic arrives on, which for VLAN-tagged traffic is the VLAN
interface, not its parent bridge.

**Required for every VLAN, not just VLAN 1:**

/interface list member add list=LAN interface=vlan1-clients

Repeat per-VLAN-interface as each one is built (`vlan10-mgmt`,
`vlan20-cluster`, etc.) — do not assume `bridge-lan`'s own list
membership covers its child VLAN interfaces.

**Diagnostic signature:** ping works (ICMP allowed by a separate,
interface-independent rule), SSH/HTTPS/REST API all fail identically —
check interface-list membership specifically before suspecting
certificates or service config.

### 2. A bridge port with no physical link shows INACTIVE and silently drops all traffic

`/interface bridge port print`'s `I` flag means exactly what it says —
no physical link means inactive regardless of correct bridge/VLAN
config. Not a config bug; connect a cable and it clears automatically.
Check `/interface ethernet print`'s `R` (running/link) flag early in
any "why isn't this port working" investigation, before suspecting
bridge or firewall config.

### 3. Split-tunnel VPN clients can silently blackhole newly-created local subnets

A Tunnelblick (OpenVPN) split-tunnel config, active for unrelated
reasons (reaching the MinIO state backend), was found to install a
reject/blackhole route (`!` flag in `netstat -rn`) for a newly-created
local test subnet — producing "no route to host" failures
indistinguishable at first glance from a genuine router-side problem.
Diagnose via `netstat -rn`, look for the `!` flag specifically.
**Resolution deferred** — planned fix is a second, VPN-independent
network interface for router bootstrap work, rather than narrowing the
VPN's own route directives under time pressure.

## Provider connection

```hcl
provider "routeros" {
  hosturl  = "https://192.168.11.1"
  username = "admin"
  password = var.router_password
  insecure = true
}
```

`insecure = true` is deliberate — self-signed cert on an isolated
bootstrap network. Revisit once the device reaches its final
production position.