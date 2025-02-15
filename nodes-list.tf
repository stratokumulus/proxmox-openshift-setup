########################################################
# This just builds the list of masters and workers nodes
########################################################
locals {
  nodes   = yamldecode(file("vars/nodes.yaml"))
  network = yamldecode(file("vars/network.yaml"))
  main    = yamldecode(file("vars/main.yaml"))

  service = {
    name    = format("%s-service", var.vm_name_prefix)
    cores   = local.nodes.service.cores
    ram     = local.nodes.service.ram
    ip      = local.nodes.service.ip
    macaddr = local.nodes.service.macaddr
    vmid    = local.nodes.service.vmid
    os      = local.main.service_os
    boot    = "started"
  }

  bootstrap = {
    name    = format("%s-bootstrap", var.vm_name_prefix)
    cores   = local.nodes.bootstrap.cores
    ram     = local.nodes.bootstrap.ram
    ip      = local.nodes.bootstrap.ip
    macaddr = local.nodes.bootstrap.macaddr
    vmid    = local.nodes.bootstrap.vmid
    os      = local.main.pxe_boot_os
    boot    = "stopped"
  }

  masters = {
    for index, node in local.nodes.masters :
    "master${index}" => {
      name    = format("%s-master%d", var.vm_name_prefix, index)
      cores   = node.cores
      ram     = node.ram
      ip      = node.ip
      macaddr = node.macaddr # Private MAC address. 
      vmid    = node.vmid
      os      = local.main.pxe_boot_os
      boot    = "stopped"
    }
  }

  workers = {
    for index, node in local.nodes.workers :
    "worker${index}" => {
      name    = format("%s-worker%d", var.vm_name_prefix, index)
      cores   = node.cores
      ram     = node.ram
      ip      = node.ip
      macaddr = node.macaddr # Private MAC address. 
      vmid    = node.vmid
      os      = local.main.pxe_boot_os
      boot    = "stopped"
    }
  }

  all_pxe_nodes = merge({ "bootstrap" = local.bootstrap }, local.masters, local.workers)
}
