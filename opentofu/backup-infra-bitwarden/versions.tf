terraform {
  required_version = ">= 1.7.0"

  required_providers {
    bitwarden-secrets = {
      source = "bitwarden/bitwarden-secrets"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "backup-infra-bitwarden/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style               = true
  }
}

provider "bitwarden-secrets" {
  api_url         = "https://api.bitwarden.eu"
  identity_url    = "https://identity.bitwarden.eu"
  access_token    = var.bw_access_token
  organization_id = var.bw_organization_id
}