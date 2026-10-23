# Plex ("behemoth"): same pattern as rocinante_gate / nextcloud_app.
# proxied = false is required: Cloudflare's proxy does not carry Plex's TCP 32400.
resource "cloudflare_dns_record" "behemoth_mcrn" {
  zone_id = data.cloudflare_zone.solsys_dev.id
  name    = "behemoth.mcrn"
  type    = "CNAME"
  content = "dynamic.solsys.dev"
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "plex_app" {
  zone_id = data.cloudflare_zone.solsys_dev.id
  name    = "plex.app"
  type    = "CNAME"
  content = "dynamic.solsys.dev"
  ttl     = 300
  proxied = false
}
