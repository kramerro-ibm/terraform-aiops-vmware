output "vm_ip_addresses" {
  description = "The IP address of the vSphere virtual machine"
  value       = [for vm in vsphere_virtual_machine.k3s_server : vm.default_ip_address]
}

output "haproxy_ip_address" {
  description = "The IP address of the haproxy virtual machine"
  value       = vsphere_virtual_machine.haproxy.default_ip_address
}

output "aiops_etc_hosts" {
  value       = "${vsphere_virtual_machine.haproxy.default_ip_address} aiops-cpd.haproxy.${var.base_domain}\n${vsphere_virtual_machine.haproxy.default_ip_address} cp-console-aiops.haproxy.${var.base_domain}"
  description = "Plug this into your local /etc/hosts file to properly resolve hosts for UI."
}