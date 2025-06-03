variable "vsphere_server" {
  type = string
}

variable "vsphere_user" {
  type = string
}

variable "vsphere_password" {
  type = string
}

variable "datacenter_name" {
  type        = string
  description = "The name of the vSphere Datacenter into which resources will be created."
}

variable "cluster_name" {
  type        = string
  description = "The vSphere Cluster into which resources will be created."
}

variable "datastore_name" {
  type        = string
  description = "The vSphere Datastore into which resources will be created."
}

variable "vm_network_name" {
  type = string
}

variable "template_name" {
  type = string
}

variable "nameservers" {
  type    = list(any)
  default = []
}

variable "ip" {
  type    = string
  default = "192.168.200.40"
}

variable "vsphere_folder" {
  type = string
}

variable "k3s_server_count" {
  type    = number
  default = 3
}

variable "k3s_agent_count" {
  type    = number
  default = 6
}

variable "install_aiops" {
  default     = "true"
  type        = string
  description = "Can be either 'true' or 'false'. Setting this to a string so it's easier to pass to the script"
}

variable "common_prefix" {
  type    = string
  default = "aiops"
}

variable "accept_license" {
  type    = string
  default = "false"
}

variable "ibm_entitlement_key" {
  type = string
}

variable "ignore_prereqs" {
  default     = false
  type        = bool
  description = "Ignore prerequisites checks during installation and force installation. WARNING: NON-PRODUCTION ONLY"
}

variable "mode" {
  default     = "base"
  type        = string
  description = "AIOps installation mode, options are base or extended"
  validation {
    condition     = contains(["base", "extended"], var.mode)
    error_message = "Mode must be either 'base' or 'extended'."
  }
}

variable "aiops_version" {
  type        = string
  description = "Version of AIOps to install, only versions 4.9.x has been tested"
}

variable "base_domain" {
  type    = string
  default = "gym.lan"
}
