
terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # pfsense = {
    #   source = "marshallford/pfsense"
    #   version = "0.20.0"
    # }
  }

  required_version = ">= 1.2.0"
}

provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

resource "random_password" "k3s_token" {
  length  = 55
  special = false
}

locals {
  # build the private registry URL
  private_registry = var.private_registry_repo != "" ? "${var.private_registry_host}:${var.private_registry_port}/${var.private_registry_repo}" : "${var.private_registry_host}:${var.private_registry_port}"

  total_nodes = var.k3s_server_count + var.k3s_agent_count

  # these are the minimums for base and extended deployment
  cpu_pool    = var.mode == "base" ? 136 : 162
  mem_pool_gb = var.mode == "base" ? 322 : 380

  # calculate cpus and memory needed per node
  num_cpus = max(16, ceil(local.cpu_pool / local.total_nodes))
  memory   = max(20480, ceil(local.mem_pool_gb / local.total_nodes) * 1024)
}

# provider "pfsense" {
#   url      = "https://${var.pfsense_host}" 
#   username = var.pfsense_username
#   password = var.pfsense_password
#   tls_skip_verify = true
# }