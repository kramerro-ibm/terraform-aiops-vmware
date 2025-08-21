variable "rhsm_username" {
  type = string
}

variable "rhsm_password" {
  type = string
}

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

variable "secondary_disk_size" {
  type = number
  default = 30
  description = "How big we want our disk in case we don't like defaults."
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

variable "vsphere_resource_pool" {
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

variable "install_k3s" {
  default     = "true"
  type        = string
  description = "Can be either 'true' or 'false'."
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
  type    = string
  default = ""

  validation {
    condition     = var.use_private_registry || trimspace(var.ibm_entitlement_key) != ""
    error_message = "ibm_entitlement_key must not be empty when use_private_registry is false."
  }
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

variable "use_mailcow" {
  default     = false
  type        = bool
  description = "Create and use a mailcow instance for email notifications"
}

variable "mailcow_ip" {
  type        = string
  default     = "192.168.252.100"
  description = "IP address for the mailcow instance"
}

variable "pfsense_host" {
  type        = string
  default = "192.168.252.1"
  description = "The hostname or IP address of the pfSense instance to manage."
}

variable "pfsense_username" {
  type        = string
  default     = "admin"
  description = "Username for pfSense management."
}

variable "pfsense_password" {
  type        = string
  default     = "pfsense"
  description = "Password for pfSense management."
}

variable "use_private_registry" {
  default     = false
  type        = bool
  description = "Use a private registry, something other than cp.icr.io"
}

variable "private_registry_host" {
  default     = ""
  type        = string
  description = "DNS or IP of private registry hosting the AIOps container images"

  validation {
    condition     = !(var.use_private_registry && trimspace(var.private_registry_host) == "")
    error_message = "private_registry_host must not be empty when use_private_registry is true."
  }
}

variable "private_registry_repo" {
  default     = ""
  type        = string
  description = "Repository name, to be appended to host:port when building registry URL (e.g. host:port/repo)"
}

variable "private_registry_port" {
  default     = 5000
  type        = number
  description = "Port number for private registry"
}

variable "private_registry_user" {
  default     = "registryuser"
  type        = string
  description = "Login user for private registry"
}

variable "private_registry_user_password" {
  default     = "registryuserpassword"
  type        = string
  description = "Login user password for private registry"
}

variable "private_registry_skip_tls" {
  default     = true
  type        = bool
  description = "Skip TLS verification for private registry"
}