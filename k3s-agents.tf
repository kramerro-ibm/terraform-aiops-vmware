
data "cloudinit_config" "k3s_agent_userdata" {
  count = var.k3s_agent_count

  gzip          = false
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloudinit/agent-userdata.yaml", {
      index       = "${count.index}",
      base_domain = "${var.base_domain}",
      public_key  = tls_private_key.deployer.public_key_openssh
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/cloudinit/k3s-install-agent.sh", {
      k3s_token                      = random_password.k3s_token.result,
      k3s_url                        = "haproxy.${var.base_domain}",
      accept_license                 = var.accept_license,
      ibm_entitlement_key            = var.ibm_entitlement_key,
      aiops_version                  = var.aiops_version,
      ignore_prereqs                 = var.ignore_prereqs ? true : false,
      use_private_registry           = var.use_private_registry ? true : false,
      private_registry               = local.private_registry,
      private_registry_user          = var.private_registry_user,
      private_registry_user_password = var.private_registry_user_password,
      private_registry_skip_tls      = var.private_registry_skip_tls ? "true" : "false",
      rhsm_username                  = var.rhsm_username,
      rhsm_password                  = var.rhsm_password,
      enable_selinux                 = var.enable_selinux ? "true" : "false"
    })
  }
}


locals {
  agent_metadata = [
    for i in range(var.k3s_agent_count) : templatefile("${path.module}/cloudinit/agent-metadata.yaml", {
      index       = i,
      base_domain = var.base_domain
    })
  ]
}

resource "vsphere_virtual_machine" "k3s_agent" {
  count = var.k3s_agent_count

  name             = "k3s-agent-${count.index}"
  resource_pool_id = data.vsphere_resource_pool.target_pool.id
  datastore_id     = data.vsphere_datastore.this.id

  folder = var.vsphere_folder

  num_cpus  = local.num_cpus
  memory    = local.memory
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  cdrom {
    client_device = true
  }

  network_interface {
    network_id = data.vsphere_network.this.id
  }

  wait_for_guest_net_timeout = 30

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }


  disk {
    label            = "disk1"
    size             = 25 # Size in GB
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = true
  }

  disk {
    label            = "disk2"
    size             = 120 # Size in GB
    unit_number      = 2
    eagerly_scrub    = false
    thin_provisioned = true
  }

  firmware                = "efi" # Ensure this matches your Packer template's firmware type
  efi_secure_boot_enabled = false # Disable Secure Boot during cloning

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.metadata"          = base64encode(local.agent_metadata[count.index])
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.k3s_agent_userdata[count.index].rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}