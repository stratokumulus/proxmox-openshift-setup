terraform {
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "3.0.2-rc07"
    }
  }
}

provider "proxmox" {
  pm_api_url       = var.api_url
  # Using API token (more reliable for guest agent access)
  pm_user          = var.user
  pm_password      = var.passwd                                                                                                                                                                                                                                                                                                           
  # Leave to "true" for self-signed certificates
  pm_tls_insecure = "true"
  #pm_debug        = true
}
