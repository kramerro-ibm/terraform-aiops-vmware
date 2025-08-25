[servers]
%{ for name, ip in server_ips ~}
${name} ansible_host=${ip} ansible_user=clouduser
%{ endfor }

[mail]
%{ if use_mailcow ~}
mailcow ansible_host=${mailcow_ip} ansible_user=clouduser
%{ endif ~}

[agents]
%{ for name, ip in agent_ips ~}
${name} ansible_host=${ip} ansible_user=clouduser
%{ endfor }

[all:vars]
ansible_ssh_user=clouduser
ansible_ssh_private_key_file=../id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[k3s_cluster:children]
servers
agents