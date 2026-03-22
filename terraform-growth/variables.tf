# Virtual Machine Specifications
variable "vm_name" {
  type        = string
  default     = "aap26"
  description = "The name of the virtual machine and related resources."
}

variable "vcpu" {
  type        = number
  default     = 4
  description = "Number of virtual CPUs to allocate."
}

variable "memory" {
  type        = number
  default     = 8192
  description = "Amount of RAM in MB."
}

# Storage Configuration
variable "base_image_path" {
  type        = string
  default     = "/var/lib/libvirt/images/almalinux-9-cloud-base.qcow2"
  description = "Path to the local QCOW2 cloud image on the hypervisor."
}

variable "os_disk_size" {
  type        = number
  default     = 42949672960 # 40 GiB
}

variable "data_disk_size" {
  type        = number
  default     = 26843545600 # 25 GiB
}

# Cloud-Init Configuration
variable "cloud_init_file" {
  type        = string
  default     = "cloud_init_almalinux.cfg"
  description = "The source YAML file for Cloud-Init configuration."
}

variable "cloud_init_iso_version" {
  type        = string
  default     = "v4"
  description = "Version suffix for the Cloud-Init ISO to prevent Libvirt caching issues."
}