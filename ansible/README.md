# Ansible

Configures the VMs Terraform provisions: base hardening and chrony (`roles/common`), RKE2 install/join (`roles/rke2`), the dedicated Longhorn block device (`roles/longhorn-disk`), and the one-time ArgoCD bootstrap (`roles/argocd-bootstrap`). Entry point: `site.yml`.
