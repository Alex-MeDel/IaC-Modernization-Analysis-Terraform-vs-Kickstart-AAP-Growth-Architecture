# AAP Node Provisioner — IaC Modernization Analysis
### Terraform + Cloud-Init vs. Kickstart for AAP Growth Architecture Deployment

A proof-of-concept that modernizes a legacy KVM VM provisioning workflow for Ansible Automation Platform (AAP) nodes. The project replaced an imperative Bash + Kickstart + ISO pipeline with Terraform and Cloud-Init, achieving a 95% reduction in deployment time — then pushed the approach into growth architecture storage requirements and hit a documented architectural ceiling.

---

## Results at a Glance

| | Legacy (Bash + Kickstart) | This Project (Terraform + Cloud-Init) |
|---|---|---|
| Deployment time | 15–20 minutes | ~60 seconds |
| State management | None (fire-and-forget) | Full Terraform state |
| Idempotency | No (duplicate runs fail) | Yes |
| LVM `/var` partitioning | ✅ Supported | ❌ Hard architectural limit |
| Enterprise AAP suitability | ✅ | ⚠️ Baseline only (not suited for growth architecture) |

---

## Repository Structure

```
.
├── main.tf                       # Terraform — VM, disks, Cloud-Init wiring
├── variables.tf                  # All configurable parameters
├── cloud_init_almalinux.cfg      # ✅ Working Cloud-Init config (AlmaLinux 9)
├── cloud_init_rhel10.cfg         # ❌ Broken — documents the Phase 2 ceiling
├── verify-infrastructure.yml     # Ansible playbook to validate the provisioned node
└── README.md
```

---

## Phase 1: The Working Solution

### What It Does

Running `terraform apply` will:

1. Register a local AlmaLinux 9 cloud image (QCOW2) as a base volume in libvirt
2. Clone and expand it into a 40 GiB OS disk
3. Provision a separate 25 GiB data disk for application use
4. Package `cloud_init_almalinux.cfg` into a virtual ISO and attach it to the VM
5. Boot the VM with 4 vCPUs and 8 GB RAM on the default libvirt network
6. Wait for a DHCP lease and output the VM's IP — ready for Ansible handoff

On first boot, Cloud-Init configures the system automatically: hostname, locale, timezone, package installation, user creation with passwordless sudo, firewall rules, and `/opt/aap-installer` directory creation.

### Why This Is Better Than the Old Workflow

**Speed.** A kickstart install boots a 9 GB ISO and runs a full OS installation from scratch — 15 to 20 minutes of waiting. A cloud image is a pre-installed OS snapshot. Terraform clones it in seconds; Cloud-Init configures it on first boot in under a minute.

**State management.** The original bash script had no memory of what it created. Running it twice produced duplicates or errors. Terraform tracks everything in a state file — `apply` twice with no changes does nothing, `destroy` cleans up exactly what was created, and incremental changes (more RAM, bigger disk) are applied as diffs.

**Reliability.** The bash script was a chain of imperative commands with manual guard logic — duplicate VM checks, `qemu-img create`, `chown`, `restorecon`. Terraform and libvirt handle all of that automatically through declarative configuration.

**The Kickstart + ISO problem in Terraform specifically.** Terraform marks a VM resource as "done" the moment the hypervisor API confirms creation — but with a kickstart install, the VM then spends 15+ minutes doing a full OS installation that Terraform cannot track. The tool is forced into fire-and-forget mode, defeating the point of using a declarative IaC tool. Cloud images don't have this problem because the OS is already installed.

### Usage

```bash
# Initialize the provider
terraform init

# Preview what will be created
terraform plan

# Provision the VM
terraform apply
```

Terraform outputs the VM's IP on completion:
```
Outputs:
vm_ip = "192.168.x.x"
cloud_init_info = {
  source_file = "cloud_init_almalinux.cfg"
  volume_name = "commoninit-aap26-v4.iso"
}
```

**Verify the node with Ansible:**
```bash
ansible-playbook -i "<YOUR_TERRAFORM_IP>," -u alex --ask-pass verify-infrastructure.yml
```

The playbook checks SSH connectivity, OS family (EL9), hostname (`aap26.home.lab`), and the existence of `/opt/aap-installer`.

**Tear down:**
```bash
terraform destroy
```

### Configuration

All parameters are in `variables.tf`. Override any of them with a `.tfvars` file or `-var` flags:

| Variable | Default | Description |
|---|---|---|
| `vm_name` | `aap26` | VM name and resource prefix |
| `vcpu` | `4` | Virtual CPU count |
| `memory` | `8192` | RAM in MB |
| `os_disk_size` | `42949672960` | OS disk size (40 GiB) |
| `data_disk_size` | `26843545600` | Data disk size (25 GiB) |
| `base_image_path` | AlmaLinux 9 QCOW2 path | Path to cloud image on hypervisor |
| `cloud_init_file` | `cloud_init_almalinux.cfg` | Cloud-Init user-data source |
| `cloud_init_iso_version` | `v4` | Version suffix — increment to bust libvirt's ISO cache |

> **Note on `cloud_init_iso_version`:** libvirt caches Cloud-Init ISOs by name and won't re-read the config if the name hasn't changed. Increment this variable during iterative development to force a re-read.

---

## Phase 2: The Architectural Ceiling

### The Goal

The original kickstart file carved explicit LVM volumes for `/var` and `/home` — a requirement for AAP growth architecture deployments because Podman stores container data in `/var/lib/containers`. Properly sizing and isolating that volume is part of the growth architecture node spec. The goal was to replicate this pre-boot storage layout using Cloud-Init.

### Why It Fails

`cloud_init_rhel10.cfg` documents this attempt. The failure is not a configuration error — it is a fundamental timing constraint.

**Kickstart** runs from the Anaconda installer environment *before* the OS exists on the disk. The target partition table is a blank slate. It can format LVMs and assign mount points freely.

**Cloud-Init** runs *during* the boot sequence of an already-running OS. By the time `runcmd` fires, `systemd`, `journald`, and `NetworkManager` all have open file descriptors inside `/var`. Attempting to unmount and remount `/var` over a live system causes those daemons to lose access to their sockets and logs, resulting in a kernel panic and a dead SSH daemon.

Cloud-Init's native `disk_setup`, `fs_setup`, and `mounts` modules share the same constraint — they run after the OS is live and cannot safely repartition a mounted root filesystem.

### The Enterprise Trade-off

A workaround exists: mount the LVM to a non-standard path like `/opt/aap-data` post-boot via Ansible, then reconfigure Podman's storage driver to point there. However, this was ruled out for this use case:

- AAP relies on Podman, which natively expects container data in `/var/lib/containers`
- Reconfiguring application data paths outside standard Linux conventions creates technical debt
- It compromises vendor supportability — Red Hat Support expects the standard layout

**Conclusion:** For growth architecture deployments where pre-boot LVM partitioning, vendor supportability, and long-term maintainability are requirements, the Kickstart workflow remains the correct choice. For standard single-node or stateless workloads, the Terraform + Cloud-Init pipeline is the superior modern approach.

The second disk (`aap26_data.qcow2`, provisioned as `/dev/vdb`) included in `main.tf` is the pragmatic middle ground — a blank 25 GiB volume attached to the VM, ready to be partitioned and mounted post-boot via Ansible to whatever path the deployment requires.

---

## Prerequisites

- KVM/libvirt on the host
- Terraform >= 1.0 with the `dmacvicar/libvirt` provider (`~> 0.7.6`)
- AlmaLinux 9 QCOW2 cloud image downloaded to the path set in `base_image_path`
- Ansible (for `verify-infrastructure.yml`)