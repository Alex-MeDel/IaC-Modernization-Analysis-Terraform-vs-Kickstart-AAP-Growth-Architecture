# AAP Node Provisioner — Terraform + Cloud-Init

Provisions an Ansible Automation Platform (AAP) node on a local KVM/libvirt hypervisor using **Terraform** and **Cloud-Init**. This replaces the original bash script + kickstart + ISO workflow with a modern, declarative, and dramatically faster approach.

---

## What This Does

Running `terraform apply` will:

1. Register a local AlmaLinux 9 cloud image (QCOW2) as a base volume in libvirt
2. Clone and expand that image into a 40 GiB VM-specific disk
3. Package `cloud_init.cfg` into a tiny virtual ISO and attach it to the VM
4. Boot the VM with 4 vCPUs and 8 GB RAM (Changeable), connected to the default libvirt network
5. Wait for a DHCP lease and output the VM's IP address — ready to hand off to Ansible

On first boot, Cloud-Init configures the system automatically: sets the hostname, locale, timezone, installs packages, creates the `jumedina` user with sudo access and an SSH key, sets firewall rules, and creates `/opt/aap-installer`.

---

## Why This Is Better Than the Old Way

The original workflow was: run a bash script → pick an ISO → boot a kickstart installation → wait.

That process has some fundamental problems that this approach solves.

### Speed: ~60 seconds vs. 15–20 minutes

A kickstart install boots from a 9 GB ISO and runs a full OS installation — partitioning disks, installing packages from scratch, running `%post` scripts. That takes 15 to 20 minutes of waiting with no feedback.

A cloud image is a pre-installed (You can install any cloud image and change base-cloud-image block in main.tf if you want different OS), pre-optimized OS snapshot. Terraform clones it in seconds. Cloud-Init runs its configuration on the first boot in under a minute. The VM is SSH-accessible almost immediately after `terraform apply` finishes.

### State Management: Declarative vs. Fire-and-Forget

The bash script has no memory of what it created. Run it twice and you get duplicates, errors, or silent failures. Deleting a VM means manually tracking down what was created and cleaning it up.

Terraform tracks everything in a state file. Running `terraform apply` twice with no config changes does nothing — it already matches the desired state. `terraform destroy` tears down exactly what was created, nothing more. Making a change (like bumping RAM or adding a disk) means editing the config and applying again — Terraform figures out the diff.

### Reliability: Declarative Config vs. Error-Prone Scripting

The bash script is a chain of imperative commands with if/else branches, each of which is a potential failure point. Terraform's HCL is declarative — you describe what you want, not how to get there, and the provider handles the execution.

### The Kickstart + ISO Problem in Terraform Specifically

Kickstart via ISO is especially awkward in Terraform. Terraform considers a VM resource "done" the moment the hypervisor API reports it created — but with a kickstart install, the VM then spends the next 15+ minutes doing hidden background work (the actual installation) that Terraform can't track. The tool is forced to act like a fire-and-forget bash script, which defeats the entire point of using a declarative IaC tool. Cloud images don't have this problem because the OS is already installed; the VM is genuinely ready when Terraform says it is.

---

## Repository Structure

```
.
├── main.tf                   # Terraform configuration
├── cloud_init.cfg            # Cloud-Init user-data (replaces the kickstart)
├── verify-infrastructure.yml # Ansible playbook to validate the provisioned node
└── README.md
```

---

## Prerequisites

- KVM/libvirt installed and running on the host
- Terraform >= 1.0
- The `dmacvicar/libvirt` Terraform provider (`~> 0.7.6`)
- An AlmaLinux 9 QCOW2 cloud image downloaded to `/var/lib/libvirt/images/almalinux-9-cloud-base.qcow2` (OR your prefered cloud image, with minor changes to main.tf)
- Ansible (for running the verification playbook)

---

## Usage

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Review the Plan

```bash
terraform plan
```

### 3. Provision the VM

```bash
terraform apply
```

Terraform will output the VM's IP address when complete:

```
Outputs:
vm_ip = "192.168.x.x"
```

### 4. Verify the Node (Optional)

Run the included Ansible playbook against the new VM to confirm everything Cloud-Init configured is correct:

```bash
ansible-playbook -i "<YOUR_TERRAFORM_IP>," -u <USERNAME> verify-infrastructure.yml
```

The playbook checks:
- SSH and Python connectivity
- OS is Enterprise Linux 9 (AlmaLinux or RHEL)
- Hostname is set to `aap26.home.lab`
- `/opt/aap-installer` directory exists

### 5. Tear Down

```bash
terraform destroy
```

Cleanly removes the VM, its disk, and the Cloud-Init ISO. No manual cleanup needed.

---

## Configuration

To adjust VM specs, edit the relevant fields in `main.tf`:

| Setting | Location in `main.tf` | Default |
|---|---|---|
| vCPUs | `libvirt_domain.aap_vm.vcpu` | 4 |
| RAM | `libvirt_domain.aap_vm.memory` | 8192 MB |
| Disk size | `libvirt_volume.os_disk.size` | 40 GiB |
| Base image path | `libvirt_volume.rhel_base.source` | `/var/lib/libvirt/images/almalinux-9-cloud-base.qcow2` |

To change users, packages, firewall rules, or the hostname, edit `cloud_init.cfg`.