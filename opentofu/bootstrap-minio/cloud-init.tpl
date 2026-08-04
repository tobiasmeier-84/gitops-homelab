#cloud-config
hostname: iapetus
fqdn: iapetus.orbit.solsys.dev

users:
  - name: admin
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ${ssh_public_key}

package_update: true
packages:
  - wget

write_files:
  - path: /etc/systemd/system/minio.service
    content: |
      [Unit]
      Description=MinIO
      After=network-online.target
      Wants=network-online.target

      [Service]
      User=minio-user
      Group=minio-user
      EnvironmentFile=/etc/default/minio
      ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES $MINIO_OPTS
      Restart=always
      RestartSec=5

      [Install]
      WantedBy=multi-user.target

  - path: /etc/default/minio
    content: |
      MINIO_VOLUMES="/data/minio"
      MINIO_OPTS="--console-address :9001"
      MINIO_ROOT_USER=${minio_root_user}
      MINIO_ROOT_PASSWORD=${minio_root_password}
    permissions: '0600'

runcmd:
  - useradd -r minio-user -s /sbin/nologin || true
  - mkdir -p /data/minio
  - chown -R minio-user:minio-user /data/minio
  - wget -q https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
  - chmod +x /usr/local/bin/minio
  - systemctl daemon-reload
  - systemctl enable --now minio