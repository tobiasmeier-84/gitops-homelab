resource "azurerm_resource_group" "backup" {
  name     = "rg-backup-chain-b-key"
  location = "switzerlandnorth"
}

resource "azurerm_key_vault" "chain_b_key" {
  name                       = "kv-solsys-chainb"
  resource_group_name        = azurerm_resource_group.backup.name
  location                   = azurerm_resource_group.backup.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.admin_object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  # Backup CronJob identity. Must stay inline: the inline access_policy blocks are
  # authoritative for this vault, so a separate azurerm_key_vault_access_policy
  # resource is silently removed again on the next vault update.
  access_policy {
    tenant_id = var.tenant_id
    object_id = azuread_service_principal.backup_writer.object_id

    secret_permissions = [
      "Get", "Set", "List", "Delete", "Purge"
    ]
  }
}

resource "azuread_application" "backup_writer" {
  display_name = "backup-chain-b-key-writer"
}

resource "azuread_service_principal" "backup_writer" {
  client_id = azuread_application.backup_writer.client_id
}

resource "azuread_application_password" "backup_writer" {
  application_id = azuread_application.backup_writer.id
  display_name   = "backup-cronjob-secret"
}

output "backup_writer_client_id" {
  value = azuread_application.backup_writer.client_id
}

output "backup_writer_client_secret" {
  value     = azuread_application_password.backup_writer.value
  sensitive = true
}


# ---- Per-app backup key vaults (ADR-0054) -------------------------------------------------
# One vault + one service principal per app. The vault name is kv-solsys-<app>-bk (Key Vault
# names are global and limited to 24 characters, hence the app-name check). The service
# principal may only reach its own vault; the operator keeps full access for restores.
# Adding an app = adding its name here (and in backup-infra-backblaze / backup-infra-ovhcloud).
variable "backup_apps" {
  description = "Apps with their own backup credentials. Their backup object names start with '<app>-'."
  type        = set(string)
  default     = ["forscher"]

  validation {
    condition     = alltrue([for a in var.backup_apps : can(regex("^[a-z][a-z0-9]{1,9}$", a))])
    error_message = "App names: 2-10 characters, lowercase letters and digits, starting with a letter."
  }
}

resource "azuread_application" "app_backup_writer" {
  for_each     = var.backup_apps
  display_name = "backup-${each.key}-key-writer"
}

resource "azuread_service_principal" "app_backup_writer" {
  for_each  = var.backup_apps
  client_id = azuread_application.app_backup_writer[each.key].client_id
}

resource "azuread_application_password" "app_backup_writer" {
  for_each       = var.backup_apps
  application_id = azuread_application.app_backup_writer[each.key].id
  display_name   = "backup-cronjob-secret"
}

resource "azurerm_key_vault" "app_backup" {
  for_each                   = var.backup_apps
  name                       = "kv-solsys-${each.key}-bk"
  resource_group_name        = azurerm_resource_group.backup.name
  location                   = azurerm_resource_group.backup.location
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7 # the minimum; the backup job also purges deleted keys at once
  purge_protection_enabled   = false

  access_policy {
    tenant_id = var.tenant_id
    object_id = var.admin_object_id

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover"
    ]
  }

  # Must stay inline (see the comment at kv-solsys-chainb above).
  access_policy {
    tenant_id = var.tenant_id
    object_id = azuread_service_principal.app_backup_writer[each.key].object_id

    secret_permissions = [
      "Get", "Set", "List", "Delete", "Purge"
    ]
  }
}

output "app_backup_vaults" {
  description = "Per-app Chain A key vault credentials: tofu output -json app_backup_vaults"
  value = {
    for app, v in azurerm_key_vault.app_backup : app => {
      vault_url     = trimsuffix(v.vault_uri, "/")
      tenant_id     = var.tenant_id
      client_id     = azuread_application.app_backup_writer[app].client_id
      client_secret = azuread_application_password.app_backup_writer[app].value
    }
  }
  sensitive = true
}
