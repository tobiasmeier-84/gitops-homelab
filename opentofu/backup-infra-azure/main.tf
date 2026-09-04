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

resource "azurerm_key_vault_access_policy" "backup_writer" {
  key_vault_id = azurerm_key_vault.chain_b_key.id
  tenant_id    = var.tenant_id
  object_id    = azuread_service_principal.backup_writer.object_id

  secret_permissions = ["Get", "Set", "List"]
}

output "backup_writer_client_id" {
  value = azuread_application.backup_writer.client_id
}

output "backup_writer_client_secret" {
  value     = azuread_application_password.backup_writer.value
  sensitive = true
}