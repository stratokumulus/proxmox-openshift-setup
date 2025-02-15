##############################
# Creating cloud-init devices.
##############################
resource "proxmox_vm_qemu" "cloudinit-nodes" {
  name        = local.service.name
  vmid        = local.service.vmid
  target_node = var.target_host
  clone       = local.service.os
  full_clone  = true
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  agent       = 1
  tags        = "okd,service"
  vm_state    = local.service.boot # start once created


  cores    = local.service.cores
  memory   = local.service.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disks {
    scsi {
      scsi0 {
        disk {
          storage = "vm-data"
          size    = "120G"
        }
      }
    }
    ide {
      ide0 {
        cloudinit {
          storage = "vm-data"
        }
      }
    }
  }
  network {
    id      = 0
    model   = "virtio"
    bridge  = local.network.bridge
    tag     = local.network.vlan
    macaddr = local.service.macaddr
  }

  # cloud-init config 
  cicustom   = "vendor=local:snippets/centos-qemu-agent.yml" # This installs the Qemu Guest Agent. Install the file in /var/lib/vz/snippets on proxmox host
  ciupgrade  = true
  nameserver = local.network.resolver
  ipconfig0  = "ip=dhcp"
  skip_ipv6  = true
  ciuser     = var.ansible_user
  cipassword = var.ansible_pwd
  sshkeys    = var.ansible_ssh_public_key
}

###################################
# Creating all PXE booting devices.
###################################
resource "proxmox_vm_qemu" "pxe-nodes" {
  for_each    = local.all_pxe_nodes
  name        = "okd-${each.key}"
  vmid        = each.value.vmid
  target_node = var.target_host
  clone       = each.value.os
  full_clone  = true
  boot        = "order=scsi0;net0" # "c" by default, which renders the coreos35 clone non-bootable. "cdn" is HD, DVD and Network
  agent       = 0
  tags        = "okd"
  vm_state    = each.value.boot # start once created

  cores    = each.value.cores
  memory   = each.value.ram
  scsihw   = "virtio-scsi-pci"
  bootdisk = "scsi0"
  hotplug  = 0

  disk {
    slot    = "scsi0"
    size    = "120G"
    type    = "disk"
    storage = "VM-DATA"
    #iothread = 1
  }
  network {
    id      = 0
    model   = "virtio"
    bridge  = local.network.bridge
    tag     = local.network.vlan
    macaddr = each.value.macaddr
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("templates/hosts.tmpl",
    {
      service_ip   = local.service.ip
      bootstrap_ip = local.bootstrap.ip
      masters      = [for j in local.masters : j.ip]
      workers      = [for j in local.workers : j.ip]
    }
  )
  filename = "inventory/hosts.ini"
}
