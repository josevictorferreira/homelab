# Homelab

My custom Homelab server configuration.

## Install

Use the `make help` command to check available commands


## Tools

- A minimal Rocky Linux 9 VM in proxmox. 
- K3s single node cluster.
- K9s to manage the cluster from the outside.
- Helm and Helmfile to easily install/upgrade charts.


## Proxmox

- Remember to disable enterprise repository on pve -> Updates -> Repositories.

- On PVE1, create a new network named `vmbr1` with CIDR `192.168.10.0` and later assign a new network bridge in it's VMs. This is needed for Pihole be accessible from outside the main network.


## K3s Cluster

Edit `/etc/systemd/system/k3s.service` and add `--disable=traefik` and `--disable=servicelb` to the `ExecStart` line.

Also remove the file `sudo rm /var/lib/rancher/k3s/server/manifests/traefik.yaml`

To remove all existing and klipper resources:
```bash
kubectl delete all -n kube-system --selector 'app=traefik'
kubectl delete all -n kube-system --selector 'app=klipper-lb'
```


## NordVPN

In case you have setted the secret access key in sops-nix, run the following to fetch the wireguard private key:
```console
curl -s -u token:$(cat /run/secrets/nordvpn_access_token) https://api.nordvpn.com/v1/users/services/credentials
```


Or if in arch linux, after downloading nordvpn cli, run the following to get wireguard private key:

```bash
nordvpn login --legacy
sudo wg show nordlynx private-key
```

Then paste the private key to the values env wireguard variable.


## GPU Passthrough

1. Enable IOMMU on Proxmox Nodes

- Edit the file `/etc/default/grub` and add `GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"` to it.
- Update grub `update-grub`
- Enable IOMMU kernel module and after that reboot:
```bash
echo "vfio-pci" >> /etc/modules
echo "kvmgt" >> /etc/modules
echo "intel_iommu=on" >> /etc/modules
```

2. Pass GPU to VMs:

- Find GPU device ID with `lspci -nn | grep VGA`
- Bind it to vfio-pci:
```bash
echo "options vfio-pci ids=8086:9bc8" > /etc/modprobe.d/vfio.conf
```
- Add GPU x to your VM, edit the `/etc/pve/qemu-server/<VM_ID>.conf` and add:
```
machine: q35
hostpci0: 00:02.0,pcie=1,x-vga=1
```

3. Install intel Drivers on VMs:

- Add rpm fusion to Rocky Linux:
```bash
sudo dnf install --nogpgcheck https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm
sudo dnf install --nogpgcheck https://mirrors.rpmfusion.org/free/el/rpmfusion-free-release-$(rpm -E %rhel).noarch.rpm https://mirrors.rpmfusion.org/nonfree/el/rpmfusion-nonfree-release-$(rpm -E %rhel).noarch.rpm
```

Install Intel GPU Driver:
```bash
sudo dnf install -y intel-media-driver clinfo
```
