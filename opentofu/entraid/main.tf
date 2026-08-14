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

  app_role {
    id                   = random_uuid.app_role_ids["belt-captain"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Captain"
    description          = "Full Proxmox administrator access"
    value                = "belt.captain"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.app_role_ids["belt-crew"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Crew"
    description          = "Scoped Proxmox VM operator access"
    value                = "belt.crew"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.app_role_ids["belt-passenger"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Passenger"
    description          = "Read-only Proxmox access"
    value                = "belt.passenger"
    enabled              = true
  }
}

locals {
  # All 15 groups defined now, even the 2 reserved domains — cheap to
  # pre-declare, and means station-/mcrn- need no renaming later once
  # they become actionable (same "reserve now" pattern as ADR-0035's
  # Earth/Mars naming space).
  rbac_domains = ["belt", "agatha-king", "station", "mcrn"]
  rbac_tiers   = ["captain", "crew", "passenger"]

  rbac_groups = {
    for pair in setproduct(local.rbac_domains, local.rbac_tiers) :
    "${pair[0]}-${pair[1]}" => {
      domain = pair[0]
      tier   = pair[1]
    }
  }
}

resource "azuread_group" "rbac" {
  for_each = local.rbac_groups

  display_name     = each.key
  security_enabled = true
  description       = "${each.value.tier} tier for ${each.value.domain} — see docs/adr/0042-cross-service-rbac.md"
}

# ---- You, as Captain, on the two domains actually wired today ----

data "azuread_user" "admin" {
  user_principal_name = var.admin_upn
}

resource "azuread_group_member" "admin_belt_captain" {
  group_object_id  = azuread_group.rbac["belt-captain"].object_id
  member_object_id = data.azuread_user.admin.object_id
}

resource "azuread_group_member" "admin_agatha_king_captain" {
  group_object_id  = azuread_group.rbac["agatha-king-captain"].object_id
  member_object_id = data.azuread_user.admin.object_id
}

resource "random_uuid" "app_role_ids" {
  for_each = toset(["belt-captain", "belt-crew", "belt-passenger"])
}

resource "azuread_service_principal" "proxmox_homelab" {
  client_id = azuread_application.proxmox_homelab.client_id
}

resource "azuread_app_role_assignment" "belt" {
  for_each = toset(["belt-captain", "belt-crew", "belt-passenger"])

  app_role_id         = random_uuid.app_role_ids[each.key].result
  principal_object_id = azuread_group.rbac[each.key].object_id
  resource_object_id  = azuread_service_principal.proxmox_homelab.object_id
}