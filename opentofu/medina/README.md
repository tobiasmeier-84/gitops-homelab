# medina (MikroTik RB5009UG+S+IN) — bootstrap notes

Operational notes for bootstrapping and troubleshooting this device.
See `docs/adr/0051-mikrotik-router-replacement.md` for the architecture
decisions and full target-state design.

## Current status

Router successfully bootstrapped to a minimal working state: bridge +
VLAN 1 only, single port (`ether3`). Confirmed working end-to-end (SSH,
HTTPS, REST API). **Not yet done:**
- Additional ports (4-8, SFP+ reserved for future switch)
- Deferred VLANs (60 for old servers, 10/20/30/40/50 for
  MGMT/CLUSTER/STORAGE/DMZ-INGRESS/EGRESS)
- Firewall rules (14-rule explicit-allow set) and NAT (4 port forwards)
- WireGuard
- **OpenTofu import of the manually-created state below** — next
  session should start here, using `tofu import` against each
  resource, rather than `tofu apply` (which will hit "already exists"
  conflicts against manually-created resources)

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