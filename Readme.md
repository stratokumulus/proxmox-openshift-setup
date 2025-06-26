# Deploying OKD/OCP with Terraform and Ansible on Proxmox

## TL;DR

Configure what you need in the vars/*yaml files, run terraform, run Ansible, sit back, relax.

## Some words of wisdom

First of all : if you're deploying this as-is in production, you're going to run into security problems. Guaranteed. This below is a lab setup, made to install and learn OpenShift/OKD in a lab environment. I'm doing dumb stuff, like turning off SELinux, and turning the host firewall off. So yeah, don't try this at work, kids. And I take no responsibility if you're having security issues. 

Also, before anyone wants to yell at me that my code suck : yes. Yes, it does. Like every normal coder exploring stuff, I first made it work. And now I'm gradually improving it. My Ansible playbook has several "shell:" sections ! Yikes ! 

I can say that a lot of VMs died while I worked on this automated deployment. Every time I ran into an issue, I probably started and killed the 8 VMs 10x a day, for many days in a row.

## Changelog, sort of ... 

Last push:
- moved somes tasks from the main code to task files. Cleaner and easier to read, but functionnality stays the same
- added tags, so that you can skip what you don't need (for instance, if you have an external DNS config and don't need to set it up, just run the playbook with `--skip dns`). More tags to come

Previous changes : 
- the full install is now 100% hands free. The playbook will install all services and fire up the OKD/OCP nodes (as long as you're on Proxmox)
- I've added the OCP config as well as the existing OKD. Chose you poison ... 
- I've added a variable to select the version to install. 
- Cilium is an optional CNI, and its version is configurable too from the `main.yaml` file 
- the nodes are also now fully described in a YAML file (so only one place to configure both Terraform and Ansible)
- I've added a section for when doing air-gapped install (but the mirroring is left as an exercise to the reader)
- I'm using a Cent0S 10 cloud-init setup

### Setting things up

You will need the following : 
- A Proxmox server that can run 8 VMs (the temporary bootstrap, the control plane nodes, and the worker ones). I give them 16GB and 4 CPUs each. 
- (Optional) A dedicated subnet/VLAN (I used VLAN2 in my config : vmbr1, tag2 - it allows me to mess with a DHCP/DNS config without impacting my main network)
- A CentOS cloudinit template to clone
- A template of a PXE boot client to clone - no OS, it'll be provided by the PXE boot (not necessary though, the VMs could be created on the fly wihout cloning). Named `pxe-client` on my proxmox.
- A resource pool (aka a folder) to show all Openshift VMs in a single view. Not mandatory, but my code uses it.

(The next 3 may need to run on the "service" host if your network doesn't offer it : )
- a DNS server
- a TFTP server (to boot machines using PXE)
- a Web server (for accessing the ignition files)

- a pull secret in "./files/pull_secret.txt". If you don't have a pull secret, either get one from RedHat, or use '{"auths":{"fake":{"auth": "aWQ6cGFzcwo="}}}' as the file content - note the single quotes surrounding the whole string !
- (Optional) A kitten happily sleeping in a box on your desk. 

![center](./files/okd-openshift.png)

Optionnally, you can also create the DHCP server on the service node (which is what I used to do, by I'm doing this on another server nowadays)

### The hosts 

I hardcoded *private* MAC addresses for my VMs. The way to make a private (unicast) MAC address is to have the least significant bit not set, and the second-least significant bit of the most significant byte set. So, the 8 bits of the first byte in the MAC address must be `xxxxxx10`. So for instance, x2 would work (`xxxxxx10`). x3 wouldn't (`xxxxxx11`) x4 wouldn't either (`xxxxx100`). x6 would work. x8 wouldn't. xA would work. xC wouldn't. xE would work. xG wouldn't, but for a totally different reason :D (xOxO only works if we're intimate enough). 

So I'm chosing 7A (1111010) for the first byte. All my labs that require a private MAC address are in my 7A: scope. 

| Name      | IP            | Mac Address       | Role                                   | OS               | PXE Boot |
| --------- | ------------- | ----------------- | -------------------------------------- | ---------------- | -------- |
| master0   | 192.168.2.190 | 7A:00:00:00:03:01 | Control plane node #1                  | FCOS             | Yes      |
| master1   | 192.168.2.191 | 7A:00:00:00:03:02 | Control plane node #2                  | FCOS             | Yes      |
| master2   | 192.168.2.192 | 7A:00:00:00:03:03 | Control plane node #3                  | FCOS             | Yes      |
| worker0   | 192.168.2.193 | 7A:00:00:00:03:04 | Worker node #1                         | FCOS             | Yes      |
| worker1   | 192.168.2.194 | 7A:00:00:00:03:05 | Worker node #2                         | FCOS             | Yes      |
| worker2   | 192.168.2.195 | 7A:00:00:00:03:06 | Worker node #3                         | FCOS             | Yes      |
| bootstrap | 192.168.2.189 | 7A:00:00:00:03:07 | Bootstrap, needed to start the cluster | FCOS             | Yes      |
| service   | 192.168.2.196 | 7A:00:00:00:03:08 | DNS, DHCP, Load balancer, web server   | Ubuntu 20/CentOS | No       |

The `hosts.ini` will be created based on the static IP addresses. I went the full dynamic route, only to get hit by some funky errors in the Proxmox terraform provider, which always used the same two VM IDs (for 8 nodes, doesn't help), and another annoying bug that forced me to got the static route until all this gets fixed.

### The configuration

The following services will be configured and started on the service host:  

- a DNS server, also pointing to my main resolver (I'm using PiHole in my main network, so I added the openshift *.apps.<cluserid><domain name> in the PiHole `dnsmasq.d/custom.conf` to forward all queries related to my OKD installation from PiHole directly to the service server).
- a TFTP server, to provide PXE boot, and get the hosts to boot with the FCOS image (downloaded by the playbook). Configured in the DHCP config for Network boot. 
- an HA Proxy, for ... proxying ... in high availability I guess ?

## How it works - the workflow

(Below is the way it used to work when the playbook wasn't fully automated. It's still valuable to read, as it provides info on how the whole magic works.)

The commands below assume you're a bit familiar with Unix and Kubernetes. Start by creating the VMs:

```
terraform init
terraform plan
terraform apply
```

Once done, run 
```
ansible-playbook setup-okd.yaml
```

Once successful, start the bootstrap VM. I usually wait for it to get to the first login screen, and then start the master nodes. I then SSH to the services host, and run 

```
openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info
```

Once I get the `bootstrap successful` message, I edit the file `/etc/haproxy/haproxy.cfg`, comment out all lines that contain the word `bootstrap`, then restart the HA Proxy service by running `systemctl restart haproxy.service`.

I then fire up the worker nodes, and run this on the service host : 

```
openshift-install --dir=install_dir/ wait-for install-complete --log-level=info
```

In another SSH session to the service host, I configure my kubeconfig : 

```
export KUBECONFIG=~/install_dir/auth/kubeconfig
```

Aftert 2 or 3 reboots, the worker nodes will appear to get stuck. It means that Kubernetes is waiting for their certificates to be approved : 

```
oc get csr | grep Pending
```

I had 6 then 3 certificates in Pending state (for 3 worker nodes). Approve them all until you have none pending: 

```
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
```

Then wait for all cluster operators to be properly started : 

```
watch -n 5 oc get co
```

It takes about 50m for the whole environment to be deployed, from the moment I run the playbook. But your mileage may vary.

Wait for the command `openshift-install wait-for install-complete ...` to finish, as it will give you the info you need to connect to your cluster (like the random password for the kubeadmin account).

Enjoy !

## Troubleshooting

It's the DNS. It's always the DNS. So check the DNS. And if it fails, recheck the DNS. Did I say "check the DNS" ?
(honestly, it's one of the most DNS-sensitive install I have ever played with)

### "Node not found" in worker nodes logs 

If you see error like "node worker0 not found" or something like that in the worker nodes logs, it means that the install of the workers went well, and it's now time to approve certificates :) Also, if you don't check the logs, but see that worker nodes are not ready, check first for the certificates in Pending state (same procedure for both cases):  

```
oc get csr | grep Pending
```
Then, either approve them one by one manually :
```
oc adm certificate approve <csr name>   # For each csr in pending state
```

or do them all at once (9 for me, with 3 worker nodes)
```
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
```
### Ensure you run the right FCOS for your OKD release:

List supported images with current version of OpenShift:
```
openshift-install coreos print-stream-json, and run grep for kernel, rootfs and initramfs
```

But the list in the file `vars/okd-version.yaml` has it all for you already :) 

### Check openshift deployment progress from the bootstrap node
Same for the master or worker nodes, just set the right IP address 
```
ssh ansiblebot@<IP of the service node>
ssh -i <path to private key created by Ansible> core@<bootstrap node IP>
journalctl -b -f -u release-image.service -u bootkube.service
```

You can do the same for each of the other nodes, as they all share the same SSH key.

### Bare metal install
Prepare your system as explained above, then boot the FCOS image without any config or PXE boot, and run the command below based on the role of the node (bootstrap, master or worker) 
```
coreos-installer install /dev/sda --ignition-url http://192.168.2.186:8080/okd4/[bootstrap|master|worker].ign --insecure-ignition
```

### After rebooting Proxmox, my cluster doesn't come back up

Make sure the services server is up and running. Then, start all master nodes. Once booted, started the worker nodes. 

Check if the firewall is still filtering traffic
```
systemctl stop firewalld
```

Check if the TFTP server is started
```
systemctl start tftp
```

Check if there are any pending certificates
```
oc get csr | grep Pending
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
```


### Other issues

Check your DNS config. "It's always DNS" ! I cannot emphasize this enough : DNS is critical to get this mammoth working 

I sometimes had to SSH to the bootstrap server, and add the okd-services server in /etc/hosts. Sucks. But worked. I should keep a "stable" VLAN and services for OKD, but hey, it's a lab :D 

### List of commands I use when in troubleshooting mode

Just so I can copy paste ... I will turn many of these into a post-install playbook to handle things all automatically
``` 
ssh root@192.168.1.101 "/usr/sbin/qm start 807"
openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info
ssh root@192.168.1.101 "/usr/sbin/qm start 801 && /usr/sbin/qm start 802 && /usr/sbin/qm start 803"
ssh root@192.168.1.101 "/usr/sbin/qm stop 807"
sudo systemctl restart haproxy
sudo vi /etc/haproxy/haproxy.cfg 
ssh root@192.168.1.101 "/usr/sbin/qm start 804 && /usr/sbin/qm start 805 && /usr/sbin/qm start 806"
openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info
openshift-install --dir=install_dir/ wait-for install-complete --log-level=info
cp install_dir/auth/kubeconfig ~/.kube/config
oc get csr | grep Pending
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
watch -n 5 "oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{\"\n\"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve"
```

### Todo

- [ ] Add the mirror registry as an option. Because, why not ?
- [ ] Add an option to go full dynamic (VMIDs and IP addresses) or to use pre-defined values for the nodes.  I do this with other projects, so why not here ?
- [ ] Create a new repo to create my CentOS template using code
- [ ] Automate more, and work less. I have a symphony to write. 
- [ ] Clean up the playbook even more, by using more tasks and tags 
- [ ] Make the tasks delegated to a node, so that I have one play, and not multiple ones (especially visible when I have to jump between proxmox and the service nodes)