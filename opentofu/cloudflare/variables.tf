variable "cloudflare_api_token" {
  description = "Dedicated Cloudflare API token for OpenTofu-managed DNS (Zone:DNS:Edit + Zone:Zone:Read, solsys.dev only)"
  type        = string
  sensitive   = true
}