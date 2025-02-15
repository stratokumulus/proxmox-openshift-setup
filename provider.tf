terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.1-rc6"
    }
  }
}

provider "proxmox" {
  pm_api_url  = var.api_url
  pm_user     = var.user
  pm_password = var.passwd
  # pm_api_token_id     = var.token_id
  # pm_api_token_secret = var.token_secret
  # Leave to "true" for self-signed certificates
  pm_tls_insecure = "true"
  #pm_debug        = true
}
