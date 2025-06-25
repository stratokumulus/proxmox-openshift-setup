########################################
# This just builds the list of all nodes
########################################
locals {
  nodes   = yamldecode(file("vars/nodes.yaml"))
  network = yamldecode(file("vars/network.yaml"))
  main    = yamldecode(file("vars/main.yaml"))

  service = {
    name    = format("%s-%s-service", local.main.env, local.main.target)
    cores   = local.nodes.service.cores
    ram     = local.nodes.service.ram
    ip      = local.nodes.service.ip
    macaddr = local.nodes.service.macaddr
    vmid    = local.main.vmbase + local.nodes.service.vmid
    os      = local.main.service_os
    boot    = "started"
  }

  bootstrap = {
    name    = format("%s-%s-bootstrap", local.main.env, local.main.target)
    cores   = local.nodes.bootstrap.cores
    ram     = local.nodes.bootstrap.ram
    ip      = local.nodes.bootstrap.ip
    macaddr = local.nodes.bootstrap.macaddr
    vmid    = local.main.vmbase + local.nodes.bootstrap.vmid
    os      = local.main.pxe_boot_os
    boot    = "stopped"
  }


  masters = {
    for index, node in local.nodes.masters :
    "master${index}" => {
      name    = format("%s-%s-master%d", local.main.env, local.main.target, index)
      cores   = node.cores
      ram     = node.ram
      ip      = node.ip
      macaddr = node.macaddr # Private MAC address. 
      vmid    = local.main.vmbase + node.vmid
      os      = local.main.pxe_boot_os
      boot    = "stopped"
    }
  }

  workers = {
    for index, node in local.nodes.workers :
    "worker${index}" => {
      name    = format("%s-%s-worker%d", local.main.env, local.main.target, index)
      cores   = node.cores
      ram     = node.ram
      ip      = node.ip
      macaddr = node.macaddr # Private MAC address. 
      vmid    = local.main.vmbase + node.vmid
      os      = local.main.pxe_boot_os
      boot    = "stopped"
    }
  }

  all_pxe_nodes = merge({ "bootstrap" = local.bootstrap }, local.masters, local.workers)
}
