terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
    }
  }
}

locals {
  vm_settings = {

    "okd-ctrl-1"    = { macaddr = "7A:00:00:00:03:01", cores = 4, ram = 16384, vmid = 1901, os = "pxe-client", boot = false },
    "okd-ctrl-2"    = { macaddr = "7A:00:00:00:03:02", cores = 4, ram = 16384, vmid = 1902, os = "pxe-client", boot = false },
    "okd-ctrl-3"    = { macaddr = "7A:00:00:00:03:03", cores = 4, ram = 16384, vmid = 1903, os = "pxe-client", boot = false },
    "okd-cmp-1"     = { macaddr = "7A:00:00:00:03:04", cores = 2, ram = 16384, vmid = 1904, os = "pxe-client", boot = false },
    "okd-cmp-2"     = { macaddr = "7A:00:00:00:03:05", cores = 2, ram = 16384, vmid = 1905, os = "pxe-client", boot = false },
    "okd-cmp-2"     = { macaddr = "7A:00:00:00:03:06", cores = 2, ram = 16384, vmid = 1905, os = "pxe-client", boot = false },   
    "okd-bootstrap" = { macaddr = "7A:00:00:00:03:07", cores = 4, ram = 16384, vmid = 1906, os = "pxe-client", boot = false },
    "okd-services"  = { macaddr = "7A:00:00:00:03:08", cores = 4, ram = 16384, vmid = 1907, os = "a2cent", boot = true }, # 192.168.1.165
  }
  bridge = "vmbr0"
  lxc_settings = {
  }
}

provider "proxmox" {
  pm_api_url  = var.api_url
  pm_user     = var.user
  pm_password = var.passwd
  # Leave to "true" for self-signed certificates
  pm_tls_insecure = "true"
  #pm_debug = true
}

/* Configure cloud-init User-Data with custom config file */
resource "proxmox_vm_qemu" "cloudinit-nodes" {
  for_each    = local.vm_settings
  name        = each.key
  vmid        = each.value.vmid
  target_node = var.target_host
  clone       = each.value.os
  full_clone  = false
  boot        = "cdn"           # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  oncreate    = each.value.boot # start once created
  agent       = 0

  cores    = each.value.cores
  memory   = each.value.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disk {
    slot    = 0
    size    = "100G"
    type    = "scsi"
    storage = "vmdata"
    #iothread = 1
  }
  network {
    model   = "virtio"
    bridge  = local.bridge
    macaddr = each.value.macaddr
  }
}
