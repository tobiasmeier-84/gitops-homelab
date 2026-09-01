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

resource "routeros_firewall_filter" "drop_forward" {
  chain   = "forward"
  action  = "drop"
  comment = "Default deny — must remain the last forward rule"
}

resource "routeros_firewall_filter" "allow_dns" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.53-10.10.10.54"
  dst_port     = "53"
  protocol     = "udp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "Titania/Oberon DNS"
}

resource "routeros_firewall_filter" "allow_dns_tcp" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.53-10.10.10.54"
  dst_port     = "53"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "Titania/Oberon DNS (TCP)"
}

resource "routeros_firewall_filter" "allow_ssh_dns_hosts" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.53-10.10.10.54"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to Titania/Oberon"
}

resource "routeros_firewall_filter" "allow_https_haproxy" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.40.10"
  dst_port     = "443"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "HAProxy VRRP floating IP HTTPS"
}

resource "routeros_firewall_filter" "allow_http_haproxy" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.40.10"
  dst_port     = "80"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "HAProxy VRRP floating IP HTTP"
}

resource "routeros_firewall_filter" "allow_ping" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.1-10.10.10.254"
  protocol     = "icmp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "MGMT subnet diagnostics"
}

resource "routeros_firewall_filter" "allow_ssh_haproxy_trio" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.31-10.10.10.34"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to HAProxy trio + Deimos"
}

resource "routeros_firewall_filter" "allow_ssh_rke2" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.41-10.10.10.43"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to RKE2 nodes"
}

resource "routeros_firewall_filter" "allow_minio" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.24"
  dst_port     = "9000"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "MinIO (iapetus)"
}

resource "routeros_firewall_filter" "allow_ssh_iapetus" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.24"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to iapetus"
}

resource "routeros_firewall_filter" "allow_ssh_proxmox" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.11-10.10.10.13"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to Proxmox hosts"
}

resource "routeros_firewall_filter" "allow_pve_admin" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.11-10.10.10.13"
  dst_port     = "8006"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "Proxmox admin UI"
}

resource "routeros_firewall_filter" "allow_ssh_switches" {
  chain        = "forward"
  action       = "accept"
  dst_address  = "10.10.10.2/31"
  dst_port     = "22"
  protocol     = "tcp"
  place_before = routeros_firewall_filter.drop_forward.id
  comment      = "SSH to switches (tycho, anderson)"
}

resource "routeros_ip_firewall_nat" "nat_http" {
  chain            = "dstnat"
  action           = "dst-nat"
  protocol         = "tcp"
  dst_port         = "80"
  in_interface_list = "WAN"
  to_addresses     = "192.168.101.12"
  to_ports         = "80"
  comment          = "reverse/nginx bridge HTTP"
}

resource "routeros_ip_firewall_nat" "nat_https" {
  chain            = "dstnat"
  action           = "dst-nat"
  protocol         = "tcp"
  dst_port         = "443"
  in_interface_list = "WAN"
  to_addresses     = "192.168.101.12"
  to_ports         = "443"
  comment          = "reverse/nginx bridge HTTPS (SNI-routed)"
}

resource "routeros_ip_firewall_nat" "nat_plex" {
  chain            = "dstnat"
  action           = "dst-nat"
  protocol         = "tcp"
  dst_port         = "32400"
  in_interface_list = "WAN"
  to_addresses     = "192.168.101.11"
  to_ports         = "32400"
  comment          = "Plex (plexi), direct"
}

resource "routeros_ip_firewall_nat" "nat_pomerium_ssh" {
  chain            = "dstnat"
  action           = "dst-nat"
  protocol         = "tcp"
  dst_port         = "2222"
  in_interface_list = "WAN"
  to_addresses     = "10.10.40.14"
  to_ports         = "2222"
  comment          = "Deimos/Pomerium SSH"
}

resource "routeros_interface_wireguard" "roadwarrior" {
  name        = "wireguard1"
  listen_port = 13231
}

output "wireguard_router_public_key" {
  value = routeros_interface_wireguard.roadwarrior.public_key
}

resource "routeros_interface_wireguard_peer" "mac" {
  interface       = routeros_interface_wireguard.roadwarrior.name
  public_key      = "wQwfAzNw8HwJsfFnEl+sHqylmokYn6grIbfWRnnIb0g="
  allowed_address = ["172.31.0.2/32"]
  comment         = "Tobias's Mac"
}

resource "routeros_interface_wireguard_peer" "iphone" {
  interface       = routeros_interface_wireguard.roadwarrior.name
  public_key      = "OtAi/dO0sb4Dqlzj+6tyReJoXujQekw2XG8LTpspEEg="
  allowed_address = ["172.31.0.3/32"]
  comment         = "Tobias's iPhone"
}

resource "routeros_ip_address" "wireguard" {
  address   = "172.31.0.1/24"
  interface = routeros_interface_wireguard.roadwarrior.name
}

resource "routeros_interface_list_member" "wireguard_lan" {
  list      = "LAN"
  interface = routeros_interface_wireguard.roadwarrior.name
}

resource "routeros_firewall_filter" "allow_wireguard" {
  chain       = "input"
  action      = "accept"
  protocol    = "udp"
  dst_port    = "13231"
  place_before = "*5"
  comment     = "WireGuard — necessary exception to input-chain deferral, VPN cannot function without this"
}