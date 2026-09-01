resource "routeros_interface_bridge" "lan" {
  name           = "bridge-lan"
  vlan_filtering = true
}

resource "routeros_interface_bridge_port" "lan_ports" {
  for_each  = toset(["ether3", "ether4", "ether5", "ether6", "ether7", "ether8"])
  bridge    = routeros_interface_bridge.lan.name
  interface = each.value
}

resource "routeros_interface_bridge_vlan" "vlan1" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["1"]
  untagged = ["ether3", "ether4", "ether5", "ether6", "ether7", "ether8"]
}

resource "routeros_interface_vlan" "vlan1" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan1-clients"
  vlan_id   = 1
}

resource "routeros_ip_address" "vlan1" {
  address   = "192.168.11.1/24"
  interface = routeros_interface_vlan.vlan1.name
}

resource "routeros_interface_bridge_vlan" "vlan60" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["60"]
  # deliberately no untagged/tagged ports — inert until migration
}

resource "routeros_interface_vlan" "vlan60" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan60-oldservers"
  vlan_id   = 60
}

resource "routeros_ip_address" "vlan60" {
  address   = "192.168.101.1/24"
  interface = routeros_interface_vlan.vlan60.name
}

resource "routeros_interface_list_member" "vlan60_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan60.name
}

# VLAN 10 — MGMT
resource "routeros_interface_bridge_vlan" "vlan10" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["10"]
}
resource "routeros_interface_vlan" "vlan10" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan10-mgmt"
  vlan_id   = 10
}
resource "routeros_ip_address" "vlan10" {
  address   = "10.10.10.1/24"
  interface = routeros_interface_vlan.vlan10.name
}
resource "routeros_interface_list_member" "vlan10_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan10.name
}

# VLAN 20 — CLUSTER
resource "routeros_interface_bridge_vlan" "vlan20" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["20"]
}
resource "routeros_interface_vlan" "vlan20" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan20-cluster"
  vlan_id   = 20
}
resource "routeros_ip_address" "vlan20" {
  address   = "10.10.20.1/24"
  interface = routeros_interface_vlan.vlan20.name
}
resource "routeros_interface_list_member" "vlan20_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan20.name
}

# VLAN 30 — STORAGE
resource "routeros_interface_bridge_vlan" "vlan30" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["30"]
}
resource "routeros_interface_vlan" "vlan30" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan30-storage"
  vlan_id   = 30
}
resource "routeros_ip_address" "vlan30" {
  address   = "10.10.30.1/24"
  interface = routeros_interface_vlan.vlan30.name
}
resource "routeros_interface_list_member" "vlan30_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan30.name
}

# VLAN 40 — DMZ-INGRESS
resource "routeros_interface_bridge_vlan" "vlan40" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["40"]
}
resource "routeros_interface_vlan" "vlan40" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan40-dmz"
  vlan_id   = 40
}
resource "routeros_ip_address" "vlan40" {
  address   = "10.10.40.1/24"
  interface = routeros_interface_vlan.vlan40.name
}
resource "routeros_interface_list_member" "vlan40_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan40.name
}

# VLAN 50 — EGRESS
resource "routeros_interface_bridge_vlan" "vlan50" {
  bridge   = routeros_interface_bridge.lan.name
  vlan_ids = ["50"]
}
resource "routeros_interface_vlan" "vlan50" {
  interface = routeros_interface_bridge.lan.name
  name      = "vlan50-egress"
  vlan_id   = 50
}
resource "routeros_ip_address" "vlan50" {
  address   = "10.10.50.1/24"
  interface = routeros_interface_vlan.vlan50.name
}
resource "routeros_interface_list_member" "vlan50_lan" {
  list      = "LAN"
  interface = routeros_interface_vlan.vlan50.name
}