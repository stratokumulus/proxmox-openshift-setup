# Deploying OpenShift with Terraform and Ansible on Proxmox

First of all : if you're deploying this as-is in production, you're going to run into security problems. Guaranteed. This is a lab setup, made to learn OpenShift. I'm doing dumb stuff, like turning off SELinux. So yeah, don't try this at work, kids. 

And before anyone wants to yell at me that my code suck : yes. Yes, it does. Like every normal coder exploring stuff, I first made it work. And then I'm gradually improving it. My Ansible has several "shell:" sections ! Yikes ! 



## Today, we ride OpenShift to valhalla ! 

Well, I can only say that a lot of VM died while I worked on this automated setup. 

The deployment can be done in two ways : the first one, the easiest one, is to run OKD in a separate subnet. This way, you can easily separate the DNS, DHCP, ... from your regular homelab setup. Everything will be well contained. 

The second one, funnier, is to have OKD in the same subnet as your homelab. That's what I'm doing below.

Below is the list of VMs we'll need. It's based on [Craig Robinson OKD 4.5 deployment guide](https://itnext.io/guide-installing-an-okd-4-5-cluster-508a2631cbee), plus a few more ideas I collected here and there on the net (mostly for the PXE boot part). 

### The hosts 

The Mac addresses I use for my VMs are all private (for unicast, 1st bit must be clear, and 2nd bit of the first byte must be set, so 7A is as good a value as any other acceptable one. x2 would work. x4 wouldn't. x6 would work. x8 wouldn't. xA would work. xC wouldn't. xE would work. xG wouldn't, but for a totally different reason :D xOxO could works, but only if we're intimate). 

| Name | IP | Mac Address | Role | OS |
|------|---------------|--------------------|------------------------------------|---------------------|
| ctrl-1 | 192.168.1.160 | 7A:00:00:00:02:01 | Control plane node #1 | FCOS |
| ctrl-2 | 192.168.1.161 | 7A:00:00:00:02:02 | Control plane node #2 | FCOS |
| ctrl-3 | 192.168.1.162 | 7A:00:00:00:02:03 | Control plane node #3 | FCOS |
| cmp-1 | 192.168.1.163 | 7A:00:00:00:02:04 | Worker node #1 | FCOS |
| cmp-2 | 192.168.1.164 | 7A:00:00:00:02:05 | Worker node #2 | FCOS |
| bootstrap | 192.168.1.159 | 7A:00:00:00:02:06 | Bootstrap, needed to start the cluster | FCOS |
| service | 192.168.1.165 | 7A:00:00:00:02:07 | DNS, DHCP, Load balancer, web server | Ubuntu 20/CentOS |

### The static configuration

If you want to deploy this in your homelab subnet, there's bit of preparation necessary. You must configure your DHCP server to return a TFTP server address (pointing to the service IP address), as well as a secondary DNS server, also pointing to the service IP address. If you're deploying in a separate subnet, the DHCP/DNS/TFTP can all run on the service server, which makes it easier to automatically configure reservations. Also, make sure the server supports DHCP network boot, and configure the service IP address, as well as the boot file (pxelinux.0 in my case). Using dhcpd on Linux, all this could be automated. Not in my setup.

## How it works 

First, we create the VMs using Terraform. About 1m30s in my lab. Then we run the Ansible `playbook-service.yaml` to configure the service server. This builds the ignition files, and prepares the kernel, rootfs and initramfs iles. Once this is done, we have to manually start the bootstrat VM, which will get its OS and config through the PXE boot. We give it a few minutes, as it will reboot twice, and then we boot the control plane VMs, who'll PXE their way to existence ! They will take a few minutes to boot and start the bootstrapping process. 

Monitor the progress of the installation (check the troubleshooting section below).

Once all control plane nodes are "Ready", stop the bootstrap VM, and fire up the compute nodes. 

Run the post install playbook, and you should be good to go ! 

## Todo
- [ ] Allow DNS configuration for PiHole ? Should be as simple as creating a template and append it to pihole's /etc/pihole/custom.list
- [ ] Create a generic /etc/resolv.conf file, based on J2 file and variables
- [ ] Make the playbook Ubunt/CentOS agnostic 
- [ ] Finish post-install config

## Troubleshooting

List supported images with current version of OpenShift:
```
openshift-install coreos print-stream-json
```

Check openshift deployment progress from the services host : 
```
openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info
```

Check openshift deployment progress from the bootstrap node (it takes a while): 
````
ssh -i <path to private key created by Ansible> core@<bootstrap node IP>
journalctl -b -f -u release-image.service -u bootkube.service
````