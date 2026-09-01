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