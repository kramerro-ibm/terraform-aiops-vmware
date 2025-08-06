locals {
  mailcow_metadata = templatefile("${path.module}/cloudinit/mailcow-metadata.yaml", {
    base_domain = "${var.base_domain}"
  })
}

data "cloudinit_config" "mailcow_userdata" {
  gzip          = false
  base64_encode = true

  # Main cloud-config configuration file.
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloudinit/mailcow-userdata.yaml", {
      base_domain = "${var.base_domain}"
      public_key  = tls_private_key.deployer.public_key_openssh
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/cloudinit/mailcow-register.sh", {
      rhsm_username      = var.rhsm_username,
      rhsm_password      = var.rhsm_password
    })
  }
}

# resource "pfsense_dnsresolver_hostoverride" "mailcow" {
#   count        = var.use_mailcow ? 1 : 0
#   host = "mailcow"
#   domain = var.base_domain
#   ip_addresses = [var.mailcow_ip]
#   description = "Mailcow DNS Override"
# }

resource "vsphere_virtual_machine" "mailcow" {
  count        = var.use_mailcow ? 1 : 0
  name             = "mailcow"
  resource_pool_id = data.vsphere_resource_pool.target_pool.id
  datastore_id     = data.vsphere_datastore.this.id

  folder = var.vsphere_folder

  num_cpus  = 4
  memory    = 4096
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
    size             = var.disk_size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  firmware                = "efi" # Ensure this matches your Packer template's firmware type
  efi_secure_boot_enabled = false # Disable Secure Boot during cloning

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.metadata"          = base64encode(local.mailcow_metadata)
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.mailcow_userdata.rendered
    "guestinfo.userdata.encoding" = "base64"
  }

  lifecycle {
    prevent_destroy = false
  }
}