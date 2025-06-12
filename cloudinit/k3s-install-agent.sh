#!/bin/bash

set -x

# output in /var/log/cloud-init-output.log

wait_lb() {
while [ true ]
do
  curl --output /dev/null --silent -k https://${k3s_url}:6443
  if [[ "$?" -eq 0 ]]; then
    break
  fi
  sleep 5
  echo "wait for LB"
done
}

disable_checksum_offload() {
# Wait for flannel.1 interface to appear
echo "Waiting for flannel.1 interface to be available..."
while ! ip link show flannel.1 &> /dev/null; do
  sleep 1
done
echo "flannel.1 interface detected. Disabling tx-checksum-ip-generic..."
# Disable TX checksum offloading for the flannel.1 interface to prevent packet corruption issues
# in some environments where the underlying network does not support checksum offloading properly.
# This is especially relevant in virtualized or cloud environments using Flannel as the CNI.
ethtool -K flannel.1 tx-checksum-ip-generic off
}

# use k3sadmin group to allow clouduser to run commands
nonroot_config() {
groupadd k3sadmin
usermod -aG k3sadmin clouduser

chown root:k3sadmin /usr/local/bin/k3s
chmod 750 /usr/local/bin/k3s

chown root:k3sadmin /etc/rancher/
chmod 750 /etc/rancher/

chown -R root:k3sadmin /etc/rancher/k3s/
chmod 750 /etc/rancher/k3s/

chmod 750 /etc/rancher/k3s/config.yaml

# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/
chmod 750 /var/lib/rancher/k3s/agent/etc/
# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/crictl.yaml
chmod 640 /var/lib/rancher/k3s/agent/etc/crictl.yaml
}

# wait for subscription registration to complete
while ! subscription-manager status; do
    echo "Waiting for RHSM registration..."
    sleep 10
done

# k3s won't run with nm-cloud-setup enabled
systemctl stop nm-cloud-setup.timer
systemctl disable nm-cloud-setup.timer 
systemctl stop nm-cloud-setup.service
systemctl disable nm-cloud-setup.service

# allow SELinux users to execute files that have been modified, this
# is needed for extended installation, if this is not set then the
# aimanager-aio-cr-api pods will CrashLoop due to selinux
setsebool -P selinuxuser_execmod 1

curl -LO "https://github.com/IBM/aiopsctl/releases/download/v${aiops_version}/aiopsctl-linux_amd64.tar.gz"
tar xf "aiopsctl-linux_amd64.tar.gz"
mv aiopsctl /usr/local/bin/aiopsctl

echo "Opening firewall ports"
firewall-cmd --permanent --add-port=8472/udp # Flannel VXLAN
firewall-cmd --permanent --add-port=51820/udp # Flannel + WireGuard (IPv4 traffic)
firewall-cmd --permanent --add-port=51821/udp # Flannel + WireGuard (IPv6 traffic)
firewall-cmd --permanent --add-port=10250/tcp # k3s kubelet metrics and logs (optional)
firewall-cmd --permanent --add-port=5001/tcp # Distributed registry
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services
firewall-cmd --reload

# this is not being set automatically
export HOME=/root

k3s_install_params=("--accept-license=${accept_license}")
k3s_install_params+=("--role=worker")
k3s_install_params+=("--token=${k3s_token}")
%{ if use_private_registry }
k3s_install_params+=("--registry=${private_registry}")
k3s_install_params+=("--registry-user=${private_registry_user}")
k3s_install_params+=("--registry-token=${private_registry_user_password}")
k3s_install_params+=("--insecure-skip-tls-verify=${private_registry_skip_tls}")
k3s_install_params+=("--offline")
%{ else }
k3s_install_params+=("--registry-token=${ibm_entitlement_key}")
%{ endif }
k3s_install_params+=("--app-storage /var/lib/aiops/storage")
k3s_install_params+=("--image-storage /var/lib/aiops/storage")
%{ if ignore_prereqs } 
k3s_install_params+=("--force")
%{ endif }

INSTALL_PARAMS="$${k3s_install_params[*]}"

wait_lb

until (aiopsctl cluster node up --server-url="https://${k3s_url}:6443" $INSTALL_PARAMS); do
  echo 'k3s did not install correctly'
  sleep 2
done

disable_checksum_offloa

nonroot_config