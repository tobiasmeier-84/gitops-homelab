#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.orbit.solsys.dev

users:
  - name: admin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true