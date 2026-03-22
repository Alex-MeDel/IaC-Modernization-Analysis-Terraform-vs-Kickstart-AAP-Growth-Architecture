terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# 1. The Base Cloud Image, this block can be changed to any other linux cloud image, as long as it is in the same specified directory
# Decided to go with almalinux instead of RHEL (original code) due to login requirement to download RHEL images, this can be changed to RHEL with minimum changes to code

# For RHEL 10
#resource "libvirt_volume" "rhel_base" {
#  name   = "rhel-10-base.qcow2"
#  pool   = "default"
#  source = "/var/lib/libvirt/images/rhel-10.1-x86_64-kvm.qcow2" 
#  format = "qcow2"
#}


# For almalinux - 1:1 of RHEL but no login essentially
resource "libvirt_volume" "rhel_base" {
  name   = "almalinux-9-base.qcow2"
  pool   = "default"
  source = "/var/lib/libvirt/images/almalinux-9-cloud-base.qcow2" 
  format = "qcow2"
}

# 2. The VM Specific Disk
# Clones the base image and expands it to the requested 40 GiB. (can adjust later with another terraform apply)
resource "libvirt_volume" "os_disk" {
  name           = "aap26_disk.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.rhel_base.id
  size           = var.os_disk_size
}

# 2.5. Second volume solution - for now, it just adds a second digital disk, that can be used for anything needed
# Original plan was to mount a lvm in this disk for Ansible Automation Platform, but due to limitations of cloud-images, and cloud-init, this was not possible if strictly following a standard
resource "libvirt_volume" "data_disk" {
  name   = "aap26_data.qcow2"
  pool   = "default"
  size   = var.data_disk_size
}
# 3. The Cloud-Init Data Source
# This reads your YAML file and creates the initialization ISO.
resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit-${var.vm_name}-${var.cloud_init_iso_version}.iso"
  pool      = "default"
  user_data = file("${path.module}/${var.cloud_init_file}")
}

# 4. The Virtual Machine Definition
# NOTE: Both the memory and the vpcu can be changed with a terraform apply
resource "libvirt_domain" "aap_vm" {
  name   = var.vm_name
  memory = var.memory
  vcpu   = var.vcpu

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true # Tells Terraform to wait until the VM gets an IP
  }

  # Attach the OS disk
  disk {
    volume_id = libvirt_volume.os_disk.id
  }

  # Part of 2.5 Second disk solution
  disk {
    volume_id = libvirt_volume.data_disk.id
  }

  # Attach the Cloud-Init configuration
  cloudinit = libvirt_cloudinit_disk.commoninit.id

  # Console setup for debugging and serial access
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    # Can change vnc to spice or what you want
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# 5. Outputs

# Output IP address
# This makes it easy to grab the IP for Ansible immediately after deployment.
output "vm_ip" {
  value       = libvirt_domain.aap_vm.network_interface[0].addresses[0]
  description = "The IP address of the newly provisioned AAP node."
}

# Verifies the specific YAML source file and compiled ISO name
output "cloud_init_info" {
  value = {
    source_file = var.cloud_init_file
    volume_name = libvirt_cloudinit_disk.commoninit.name
  }
  description = "Details of the Cloud-Init configuration used in this deployment."
}