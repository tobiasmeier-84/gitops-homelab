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