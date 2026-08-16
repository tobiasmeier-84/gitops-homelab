output "argocd_client_secret" {
  value     = azuread_application_password.argocd.value
  sensitive = true
}
