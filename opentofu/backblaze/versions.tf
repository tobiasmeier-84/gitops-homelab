terraform {
  required_version = ">= 1.7.0"

  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.13"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "backblaze/terraform.tfstate"
    endpoint                    = "https://iapetus.orbit.solsys.dev:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    use_path_style               = true
  }
}

provider "b2" {
  application_key_id = var.b2_management_key_id
  application_key     = var.b2_management_key
}