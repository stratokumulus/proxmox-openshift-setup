# Deploying OpenShift 4.12 with Terraform and Ansible on Proxmox

(tested with OKD 4.12.0 02-04 and 02-18)

First of all : if you're deploying this as-is in production, you're going to run into security problems. Guaranteed. This below is a lab setup, made to install and learn OpenShift in a lab environment. I'm doing dumb stuff, like turning off SELinux, and turning the host firewall off. So yeah, don't try this at work, kids. And I take no responsibility if you're having security issues. 

Also, before anyone wants to yell at me that my code suck : yes. Yes, it does. Like every normal coder exploring stuff, I first made it work. And now I'm gradually improving it. My Ansible playbook has several "shell:" sections ! Yikes ! 

I can say that a lot of VM died while I worked on this automated deployment. Before I figured out where my main bug was, I probably started and killed the 8 VMs 10x a day, for many days in a row (*my haproxy was using port 80 to answer to queries on 443 ... this one has been a nightmare to figure out*).

## TL;DR

Deploy the VMs, fire up the "service" machine, run the ansible playbook. Then fire up the bootstrap node. Then fire up the 3 master nodes. Once they're all up and running (you can see them as "ready" in the "oc get nodes" outputs), stop the bootstrap node, remove references to this node in the haproxy config, restart haproxy, and fire up the worker nodes. They'll get stuck after the 3rd boot, so approve all the certificates to "unstuck" them. Done !

### Setting things up

We will need the following : 
- A Proxmox server that can run 7 VMs, for a minimum of 22 CPUs, 112GB of RAM
- (Optional) A dedicated subnet/VLAN (I used VLAN2 in my config : vmbr1, tag2 - it allows me to mess with a DHCP/DNS config without impacting my main network)
- A template of a CentOS server to clone, created with an ansible user (`ansiblebot` for me), which has sudo privileges with no passwords. Named `a2cent` on my proxmox.
- A template of a PXE boot client to clone - no OS, it'll be provided by the PXE boot (not necessary though, the VMs could be created on the fly wihout cloning). Named `pxe-client` on my proxmox.
- A resource pool (aka a folder) to show all Openshift VMs in a single view. Not mandatory, but my code uses it.

(The next 4 will run on the "service" host : )
- a DHCP server (with reservations, for ease of use)
- a DNS server
- a TFTP server (to boot machines using PXE)
- a Web server (for accessing the ignition files)

- a pull secret in "./files/pull_secret.txt". If you don't have a pull secret, either get one from RedHat, or use '{"auths":{"fake":{"auth": "bar"}}}' as the file content - note the single quotes surrounding the whole string !
- (Optional) A kitten happily sleeping in a box on your desk.

![center](./files/okd-openshift.png)

### The hosts 

I hardcoded private MAC addresses for my VMs. The way to make a private (unicast) MAC address is to have the least significant bit not set, and the second-least significant bit of the most significant byte set. So, the 8 bits of the first byte in the MAC address must be `xxxxxx10`. So for instance, x2 would work (`00000010`). x3 wouldn't (`00000011`) x4 wouldn't either (`00000100`). x6 would work. x8 wouldn't. xA would work. xC wouldn't. xE would work. xG wouldn't, but for a totally different reason :D (xOxO only works if we're intimate enough). 

| Name | IP | Mac Address | Role | OS | PXE Boot |
|------|---------------|--------------------|------------------------------------|---------------------|-----|
| master0 | 192.168.2.190 | 7A:00:00:00:03:01 | Control plane node #1 | FCOS | Yes |
| master1 | 192.168.2.191 | 7A:00:00:00:03:02 | Control plane node #2 | FCOS | Yes |
| master2 | 192.168.2.192 | 7A:00:00:00:03:03 | Control plane node #3 | FCOS | Yes |
| worker0 | 192.168.2.193 | 7A:00:00:00:03:04 | Worker node #1 | FCOS | Yes |
| worker1 | 192.168.2.194 | 7A:00:00:00:03:05 | Worker node #2 | FCOS | Yes |
| worker2 | 192.168.2.195 | 7A:00:00:00:03:06 | Worker node #3 | FCOS| Yes |
| bootstrap | 192.168.2.189 | 7A:00:00:00:03:07 | Bootstrap, needed to start the cluster | FCOS | Yes |
| service | 192.168.2.196 | 7A:00:00:00:03:08 | DNS, DHCP, Load balancer, web server | Ubuntu 20/CentOS | No |

Please note that the `hosts.ini` file has these IP addresses hardcoded. I could make this generic, by creating another playbook, using the localhost connection, to generate the IP addresses. Or use Terraform to generate it. Or let the user do this part of the config manually. Laziness won, you'll have to adapt it yourself ! You will also need to assign the service host its static IP address. The reason I'm not using my main network DHCP server is that it doesn't allow hostnames to be sent as part of the DHCP conversation. And this installation is super tricky when it comes to DNS ... 

### The configuration

The following services will be configured and started on the service host:  

- the DHCP server, for static IP reservation of the VMs, along with a few options (like a TFTP server address pointing to the TFTP server, convenientely hosted for me on the same service host), 
- a DNS server, also pointing to the service host IP address (I'm using PiHole in my main network , so I added the openshift domain name in the PiHole `dnsmasq.d/custom.conf` to forward all queries related to my OKD installation from PiHole directly to the service server).
- a TFTP server, to provide PXE boot, and get the hosts to boot with the FCOS image (downloaded by the playbook). 
- an HA Proxy, for ... proxying ... in high availability I guess ?

## How it works - the workflow

The commands below assume you're a bit familiar with Unix and Kubernetes. Start by creating the VMs:

```
terraform init
terraform plan
terraform apply
```

Once done, run 
```
ansible-playbook playbook-services.yaml
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
For me, I had 9 certificates in Pending state (for 3 worker nodes). Approve them all at once : 

```
oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
```

Then wait for all cluster operators to be properly started : 

```
watch -n 5 oc get co
```

TookIt takes about 50m for the whole environment to be deployed, from the moment I run the playbook. But your mileage may vary.

Wait for the command `openshift-install wait-for install-complete ...` to finish, as it will give you the info you need to connect to your cluster (like the random password for the kubeadmin account).

Enjoy !

## Todo

- [ ] Create a generic /etc/resolv.conf file, based on J2 file and variables
- [ ] Generate the hosts.ini based on the IP addresses defined in vars/main.yaml
- [ ] Remove the NOPASSWD config for the ansiblebot user at the end of the playbook
- [ ] Make the playbook Ubuntu/CentOS agnostic 
- [ ] Finish post-install config
- [ ] Remove shell commands in the playbook
- [ ] Create the template image using packer (and get rid of "ansiblebot" user in favor of "ansible")
- [ ] Remove the machineNetwork from the install-config.yaml.j2 file, as this points to my own lab, and may not even be necessary
- [ ] Cache OKD files on the local machine. Not useful when you only run things once, but when you're troubleshooting, it speeds up things (it's the longest part of the playbook, so would make sense ... )

## Monitoring deployment status

Check openshift deployment progress from the services host : 
```
openshift-install --dir=install_dir/ wait-for bootstrap-complete --log-level=info
```

From then on, use "export KUBECONFIG=~/install_dir/auth/kubeconfig" to access the cluster and run the oc command. 

After starting the worker nodes:
```
openshift-install --dir=install_dir/ wait-for install-complete --log-level=info
```

This command will give you the URL, username and password to access the web console. 

In another window, I like to watch the progress of the config of the cluster operators by running 
```
watch -n 5 oc get co
```
It took about 50 minutes for me from the start of the playbook to the completed installation message.

## Troubleshooting

### "Node not found" in worker nodes logs 
### Certificate approval

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
