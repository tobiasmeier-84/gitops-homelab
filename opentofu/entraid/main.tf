resource "azuread_application" "proxmox_homelab" {
  display_name     = "proxmox-homelab"
  sign_in_audience = "AzureADMyOrg" # single tenant

   web {
    redirect_uris = [
      "https://ceres.belt.solsys.dev:8006/",
      "https://eros.belt.solsys.dev:8006/",
      "https://pallas.belt.solsys.dev:8006/",
      "https://belt.mcrn.solsys.dev/",
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
  for_each = toset([
    "belt-captain", "belt-crew", "belt-passenger",
    "agatha-king-captain", "agatha-king-crew", "agatha-king-passenger",
  ])
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

resource "azuread_application" "argocd" {
  display_name     = "argocd-agatha-king"
  sign_in_audience = "AzureADMyOrg"

  web {
    redirect_uris = [
      "https://agatha-king.gate.solsys.dev/auth/callback",
    ]
  }

  app_role {
    id                   = random_uuid.app_role_ids["agatha-king-captain"].result
    allowed_member_types = ["User"]
    display_name         = "Agatha King Captain"
    description          = "Full ArgoCD administrator access"
    value                = "agatha-king.captain"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.app_role_ids["agatha-king-crew"].result
    allowed_member_types = ["User"]
    display_name         = "Agatha King Crew"
    description          = "Sync/manage Applications, no RBAC/Project admin"
    value                = "agatha-king.crew"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.app_role_ids["agatha-king-passenger"].result
    allowed_member_types = ["User"]
    display_name         = "Agatha King Passenger"
    description          = "Read-only ArgoCD access"
    value                = "agatha-king.passenger"
    enabled              = true
  }
}

resource "azuread_service_principal" "argocd" {
  client_id = azuread_application.argocd.client_id
}

resource "azuread_application_password" "argocd" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-oidc-client-secret"
}

resource "azuread_app_role_assignment" "agatha_king" {
  for_each = toset(["agatha-king-captain", "agatha-king-crew", "agatha-king-passenger"])

  app_role_id         = random_uuid.app_role_ids[each.key].result
  principal_object_id = azuread_group.rbac[each.key].object_id
  resource_object_id  = azuread_service_principal.argocd.object_id
}

resource "random_uuid" "pomerium_app_role_ids" {
  for_each = toset(["belt-captain", "belt-crew", "belt-passenger"])
}

resource "azuread_application" "pomerium" {
  display_name     = "pomerium-mcrn"
  sign_in_audience = "AzureADMyOrg"

  web {
    redirect_uris = [
      "https://deimos.mcrn.solsys.dev/oauth2/callback",
    ]
  }

  app_role {
    id                   = random_uuid.pomerium_app_role_ids["belt-captain"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Captain"
    description          = "Full Proxmox admin access via ZTNA"
    value                = "belt.captain"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.pomerium_app_role_ids["belt-crew"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Crew"
    description          = "Scoped Proxmox VM operator access via ZTNA"
    value                = "belt.crew"
    enabled              = true
  }

  app_role {
    id                   = random_uuid.pomerium_app_role_ids["belt-passenger"].result
    allowed_member_types = ["User"]
    display_name         = "Belt Passenger"
    description          = "Read-only Proxmox access via ZTNA"
    value                = "belt.passenger"
    enabled              = true
  }
}

resource "azuread_service_principal" "pomerium" {
  client_id = azuread_application.pomerium.client_id
}

resource "azuread_application_password" "pomerium" {
  application_id = azuread_application.pomerium.id
  display_name   = "pomerium-oidc-client-secret"
}

resource "azuread_app_role_assignment" "pomerium_belt" {
  for_each = toset(["belt-captain", "belt-crew", "belt-passenger"])

  app_role_id         = random_uuid.pomerium_app_role_ids[each.key].result
  principal_object_id = azuread_group.rbac[each.key].object_id
  resource_object_id  = azuread_service_principal.pomerium.object_id
}

output "pomerium_client_secret" {
  value     = azuread_application_password.pomerium.value
  sensitive = true
}

output "pomerium_client_id" {
  value = azuread_application.pomerium.client_id
}