resource "azuread_application" "proxmox_homelab" {
  display_name     = "proxmox-homelab"
  sign_in_audience = "AzureADMyOrg" # single tenant

  web {
    redirect_uris = [
      "https://ceres.belt.solsys.dev:8006/",
      "https://eros.belt.solsys.dev:8006/",
      "https://pallas.belt.solsys.dev:8006/",
    ]
  }

  # NOTE: the existing client secret (keyId 825110c0-...) is deliberately
  # NOT managed here — secrets can't be read back via the API once
  # created, so there's nothing meaningful to import. It remains a
  # manually-managed credential, unrelated to this resource's lifecycle.
  # OpenTofu-managed secret rotation is a backlog item — see docs/BACKLOG.md.
}
