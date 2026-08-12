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