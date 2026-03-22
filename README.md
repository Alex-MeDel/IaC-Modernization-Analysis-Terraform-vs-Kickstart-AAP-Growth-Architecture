# AAP Node Provisioning: IaC Modernization & Architecture Analysis

## 📌 Executive Summary
The objective of this project was to modernize a legacy VM provisioning workflow for Ansible Automation Platform (AAP) nodes. The original architecture relied on imperative Bash scripts, ISO boot media, and Kickstart files, resulting in a 15-20 minute deployment time. 

This project successfully migrated the baseline provisioning to **Terraform** and **Cloud-Init** using AlmaLinux Cloud Images, reducing "time-to-value" by 95% (deploying in ~60 seconds). However, when attempting to replicate advanced, day-zero storage configurations (specifically, LVM carving for `/var` and `/home`), the project encountered a hard architectural ceiling within Cloud-Init, leading to a pivot back to Kickstart for enterprise compliance.

---

## 🚀 Phase 1: The Success (Speed & Declarative State)
The initial migration to Terraform and Cloud-Init was highly successful for baseline OS configuration.

* **Infrastructure as Code:** Replaced the "fire-and-forget" Bash script with Terraform, allowing for stateful lifecycle management of the KVM resources.
* **Cloud Images over ISOs:** Shifted from installing an OS from scratch via Kickstart to cloning a pre-baked QCOW2 image.
* **Results:** Deployment time dropped from 20 minutes to approximately 60 seconds. The VM booted with correct networking, SSH keys, user permissions, and firewall rules already applied, ready for an Ansible handoff.

---

## 🧱 Phase 2: The Architectural Ceiling (Cloud-Init vs. Kickstart)
The project hit a technical limitation when attempting to replicate the original Kickstart's LVM partitioning, specifically carving out a separate volume for `/var` to house AAP container data.

### The Technical Problem: Live Migration vs. Pre-Boot Formatting
* **Kickstart** operates from an installer environment *before* the OS exists on the disk. It can format LVMs and map `/var` without resistance.
* **Cloud-Init** executes *during* the boot sequence of an already-running OS. 

When a custom bash script within Cloud-Init's `runcmd` successfully created the LVMs and attempted to mount them over the live `/var` directory, the operating system locked up. Critical daemons (`systemd`, `journald`, `NetworkManager`) instantly lost access to their open file descriptors and sockets within `/var/run` and `/var/log`, causing a system panic and dead SSH daemon.

### The Enterprise Trade-off
While workarounds exist (such as using Ansible to mount the LVM to a non-critical directory like `/opt/aap-data` post-boot), discussions with an Enterprise Architect highlighted a critical compliance issue:
* AAP relies on Podman, which natively expects container data to live in `/var/lib/containers`.
* Reconfiguring application data paths outside of standard Linux conventions creates significant technical debt and compromises vendor supportability (e.g., Red Hat Support).

## 💡 Conclusion & Lessons Learned
For enterprise environments where vendor supportability and long-term maintainability outweigh raw deployment speed, the legacy Kickstart workflow remains the superior architectural choice for complex, pre-boot storage mapping. 

However, for stateless applications or standard compute nodes, the Terraform + Cloud-Init pipeline built in Phase 1 provides a vastly superior, modern IaC workflow.