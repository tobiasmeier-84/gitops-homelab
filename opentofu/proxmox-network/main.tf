# ============================================================================
# Network bridges for CLUSTER, STORAGE, DMZ-INGRESS, EGRESS (ADR-0031).
# MGMT (vmbr0) already exists via the Proxmox answer-file install.
#
# All 4 physical interfaces (enp1s0f0, enp1s0f1, enp3s0, enp4s0) are
# consistently named identically across all 3 nodes, confirmed via direct
# inspection. Each connects to a switch port in Access mode (single
# untagged VLAN, confirmed via `display this` on each port) — so these
# bridges are plain, non-VLAN-aware bridges, structurally identical to
# vmbr0. No 802.1Q tagging is needed at the Proxmox layer; VLAN
# separation is handled entirely by the switch.
#
# KNOWN GAP: pallas's STORAGE port (enp1s0f1) has a working physical
# link but the SFP+ transceiver in that port is rejected by the ixgbe
# driver ("unsupported SFP+ or QSFP module type"). The bridge is created
# regardless — it will simply carry no traffic until the module is
# swapped. See docs/BACKLOG.md.
# ============================================================================

locals {
  bridges = {
    cluster = {
      name    = "vmbr1"
      port    = "enp1s0f0"
      comment = "CLUSTER - CNI/K8s node traffic"
    }
    storage = {
      name    = "vmbr2"
      port    = "enp1s0f1"
      comment = "STORAGE - Longhorn replication"
      mtu     = 9000
    }
    dmz_ingress = {
      name    = "vmbr3"
      port    = "enp3s0"
      comment = "DMZ-INGRESS - HAProxy to ingress-nginx"
    }
    egress = {
      name    = "vmbr4"
      port    = "enp4s0"
      comment = "EGRESS - outbound only, backup/DDNS"
    }
  }

  node_bridge_pairs = {
    for pair in setproduct(var.nodes, keys(local.bridges)) :
    "${pair[0]}-${pair[1]}" => {
      node = pair[0]
      key  = pair[1]
    }
    if !(pair[0] == "pallas" && pair[1] == "storage")
  }
}

resource "proxmox_network_linux_bridge" "node_bridges" {
  for_each = local.node_bridge_pairs

  depends_on = [null_resource.storage_interface_mtu]

  node_name = each.value.node
  name      = local.bridges[each.value.key].name
  ports     = [local.bridges[each.value.key].port]
  comment   = "${local.bridges[each.value.key].comment} (${each.value.node})"
  autostart = true
  mtu       = try(local.bridges[each.value.key].mtu, null)
}

# ============================================================================
# Physical interface MTU for jumbo frames (STORAGE only). bpg/proxmox has
# no resource for raw physical interfaces (only bridges/bonds/VLANs), so
# this uses pvesh directly. Two-call pattern required — pvesh set on the
# interface only stages the change (/etc/network/interfaces.new); a
# second call to the node-level /network endpoint commits it. This is
# NOT the same as `ifreload -a`, which only reloads already-committed
# config. Discovered the hard way — see git history / docs/BACKLOG.md.
#
# Excludes pallas: its enp1s0f1 doesn't exist yet due to an SFP+ module
# incompatibility (see docs/BACKLOG.md). Add pallas back to this for_each
# once resolved.
# ============================================================================
resource "null_resource" "storage_interface_mtu" {
  for_each = toset([for n in var.nodes : n if n != "pallas"])

  connection {
    type  = "ssh"
    host  = "${each.value}.belt.solsys.dev"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "pvesh set /nodes/${each.value}/network/enp1s0f1 --type eth --mtu 9000",
      "pvesh set /nodes/${each.value}/network"
    ]
  }
}