resource "null_resource" "timezone" {
  for_each = toset(var.nodes)

  connection {
    type  = "ssh"
    host  = "${each.value}.belt.solsys.dev"
    user  = "root"
    agent = true
  }

  provisioner "remote-exec" {
    inline = [
      "timedatectl set-timezone Europe/Zurich"
    ]
  }
}

resource "proxmox_virtual_environment_dns" "nodes" {
  for_each = toset(["ceres", "eros", "pallas"])

  node_name = each.value
  domain    = "belt.solsys.dev"
  servers   = ["10.10.10.53", "10.10.10.54"]
}