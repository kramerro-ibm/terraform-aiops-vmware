
data "cloudinit_config" "k3s_server_userdata" {
  count = var.k3s_server_count

  gzip          = false
  base64_encode = true

  # cloud-config userdata 
  part {
    filename     = "init.cfg"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/cloudinit/server-userdata.yaml", {
      index       = "${count.index}",
      base_domain = "${var.base_domain}"
      public_key  = tls_private_key.deployer.public_key_openssh
    })
  }

  part {
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/cloudinit/k3s-install-server.sh", {
      vsphere_server      = var.vsphere_server,
      vsphere_user        = var.vsphere_user,
      vsphere_password    = var.vsphere_password,
      vsphere_datacenter  = var.datacenter_name,
      vsphere_folder      = var.vsphere_folder,
      k3s_token           = random_password.k3s_token.result,
      install_aiops       = var.install_aiops,
      k3s_url             = "haproxy.${var.base_domain}",
      accept_license      = var.accept_license,
      ibm_entitlement_key = var.ibm_entitlement_key,
      aiops_version       = var.aiops_version
      num_nodes           = var.k3s_agent_count + var.k3s_server_count,
      ignore_prereqs      = var.ignore_prereqs ? true : false,
      base_domain         = var.base_domain,
      mode                = var.mode
    })
  }
}

locals {
  server_metadata = [
    for i in range(var.k3s_server_count) : templatefile("${path.module}/cloudinit/server-metadata.yaml", {
      index       = i,
      base_domain = var.base_domain
    })
  ]
}

resource "vsphere_virtual_machine" "k3s_server" {
  count = var.k3s_server_count

  name             = "k3s-server-${count.index}"
  resource_pool_id = data.vsphere_compute_cluster.this.resource_pool_id
  datastore_id     = data.vsphere_datastore.this.id

  folder = var.vsphere_folder

  num_cpus  = 16
  memory    = 65536
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

  disk {
    label            = "disk3"
    size             = 120 # Size in GB
    unit_number      = 3
    eagerly_scrub    = false
    thin_provisioned = true
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  extra_config = {
    "guestinfo.metadata"          = base64encode(local.server_metadata[count.index])
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.k3s_server_userdata[count.index].rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}