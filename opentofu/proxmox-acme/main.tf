resource "proxmox_acme_account" "production" {
  name      = "production"
  contact   = ""  # matches the account's actual current (empty) state
  directory = "https://acme-v02.api.letsencrypt.org/directory"
  tos       = "https://letsencrypt.org/documents/LE-SA-v1.8-July-06-2026.pdf"
} 

resource "proxmox_acme_dns_plugin" "cftoken" {
  plugin           = "cftoken"
  api              = "cf"
  validation_delay = 0

  data_wo = {
    CF_Token = "\"${var.cloudflare_acme_token}\""
  }
  data_wo_version = 1
}

resource "proxmox_acme_certificate" "nodes" {
  for_each = toset(["ceres", "eros", "pallas"])

  node_name = each.value
  account   = proxmox_acme_account.production.name

  domains = [{
    domain = "${each.value}.belt.solsys.dev"
    plugin = proxmox_acme_dns_plugin.cftoken.plugin
  }]
}