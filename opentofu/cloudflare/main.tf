# ============================================================================
# VERIFY BEFORE EXPANDING: Cloudflare provider v5 renamed cloudflare_record
# to cloudflare_dns_record, and current docs disagree on whether zone
# lookup uses cloudflare_zone (singular, filter block) or cloudflare_zones
# (plural, list). Confirm via `tofu providers schema -json` before adding
# any real DNS resources beyond this connectivity check.
# ============================================================================

data "cloudflare_zone" "solsys_dev" {
  filter = {
    name = "solsys.dev"
  }
}

output "zone_id" {
  description = "Confirms the provider can authenticate and read real data"
  value       = data.cloudflare_zone.solsys_dev.id
}

data "cloudflare_dns_records" "all" {
  zone_id = data.cloudflare_zone.solsys_dev.id
}

output "existing_dns_records" {
  description = "Every DNS record currently in the solsys.dev zone"
  value       = data.cloudflare_dns_records.all.result
}

resource "cloudflare_dns_record" "mx_cyon" {
  zone_id  = data.cloudflare_zone.solsys_dev.id
  name     = "solsys.dev"
  type     = "MX"
  content  = "s071.cyon.net"
  priority = 10
  ttl      = 1
  proxied  = false
}

resource "cloudflare_dns_record" "txt_entraid_verification" {
  zone_id = data.cloudflare_zone.solsys_dev.id
  name    = "solsys.dev"
  type    = "TXT"
  content = "\"MS=ms60638603\""
  ttl     = 3600
  proxied = false
}

resource "cloudflare_dns_record" "txt_spf_cyon" {
  zone_id = data.cloudflare_zone.solsys_dev.id
  name    = "solsys.dev"
  type    = "TXT"
  content = "\"v=spf1 include:spf.protection.cyon.net -all\""
  ttl     = 1
  proxied = false
}