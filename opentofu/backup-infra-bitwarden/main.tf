data "bitwarden-secrets_projects" "all" {}

output "available_projects" {
  value = data.bitwarden-secrets_projects.all
}