resource "proxmox_realm_openid" "entraid" {
  realm         = "entraid"
  issuer_url = "https://login.microsoftonline.com/0b87a43d-5640-4e22-a2f2-d13394ff6191/v2.0"
  client_id     = "a4f9f82e-cf88-417b-b183-0d30883251a5"
  username_claim = "preferred_username"
  autocreate    = true

  groups_claim      = "roles"
  groups_autocreate = true

  client_key_wo         = var.entraid_client_secret
  client_key_wo_version = 1
}

resource "proxmox_virtual_environment_group" "belt_captain" {
  group_id = "belt.captain-entraid"
  comment  = "Full Proxmox admin, from Entra ID belt-captain group"
}

resource "proxmox_virtual_environment_group" "belt_crew" {
  group_id = "belt.crew-entraid"
  comment  = "Scoped VM operator, from Entra ID belt-crew group"
}

resource "proxmox_virtual_environment_group" "belt_passenger" {
  group_id = "belt.passenger-entraid"
  comment  = "Read-only, from Entra ID belt-passenger group"
}

resource "proxmox_acl" "belt_captain" {
  path     = "/"
  role_id  = "Administrator"
  group_id = proxmox_virtual_environment_group.belt_captain.group_id
  propagate = true
}

resource "proxmox_acl" "belt_crew" {
  path      = "/"
  role_id   = "PVEVMAdmin"
  group_id  = proxmox_virtual_environment_group.belt_crew.group_id
  propagate = true
}

resource "proxmox_acl" "belt_passenger" {
  path      = "/"
  role_id   = "PVEAuditor"
  group_id  = proxmox_virtual_environment_group.belt_passenger.group_id
  propagate = true
}