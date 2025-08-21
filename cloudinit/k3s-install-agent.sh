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

echo "Starting RHSM registration script (Simple Content Access enabled) at $(date)"

RHSM_USERNAME="${rhsm_username}"
RHSM_PASSWORD="${rhsm_password}"

if [[ -z "$RHSM_USERNAME" || -z "$RHSM_PASSWORD" ]]; then
    echo "ERROR: RHSM username or password not provided. Skipping registration."
    exit 1
fi

echo "Attempting to register system with RHSM..."
# With Simple Content Access, --auto-attach is generally sufficient after registration.
subscription-manager register --username="$RHSM_USERNAME" --password="$RHSM_PASSWORD" --auto-attach || {
    echo "ERROR: RHSM registration failed."
    exit 1
}
echo "RHSM registration successful. Entitlements should be available via Simple Content Access."

echo "Refreshing subscriptions and updating yum/dnf metadata..."
subscription-manager refresh || echo "WARNING: Failed to refresh subscriptions."
yum makecache || dnf makecache || echo "WARNING: Failed to refresh package cache."

echo "RHSM registration script finished at $(date)"

echo "Starting LVM disk setup at $(date)"

# Install LVM2 utilities if not already present
echo "Installing lvm2..."
yum install -y lvm2 || dnf install -y lvm2 || { echo "ERROR: Failed to install lvm2."; exit 1; }
echo "lvm2 installed."

echo "Creating logical volumes..."
processed_disks=""

for disk in $(lsblk -o NAME,TYPE | grep disk | awk '{print $1}'); do
  if ! lsblk /dev/$disk | grep -q part; then
    echo "Processing /dev/$disk"
    parted /dev/$disk --script mklabel gpt
    parted /dev/$disk --script mkpart primary 0% 100%
    pvcreate /dev/$${disk}1
    processed_disks="$processed_disks /dev/$${disk}1"
  fi
done

if [ -n "$processed_disks" ]; then
  vgcreate vg_aiops $processed_disks
else
  echo "No disks were processed."
fi

lvcreate -L 119G -n lv_storage vg_aiops
lvcreate -L 24G -n lv_rancher vg_aiops
mkfs.xfs /dev/vg_aiops/lv_storage
mkfs.xfs /dev/vg_aiops/lv_rancher
mkdir -p /var/lib/aiops/storage
mkdir -p /var/lib/rancher
mount /dev/vg_aiops/lv_storage /var/lib/aiops/storage
mount /dev/vg_aiops/lv_rancher /var/lib/rancher
echo "/dev/vg_aiops/lv_storage /var/lib/aiops/storage xfs defaults,nofail 0 2" | tee -a /etc/fstab
echo "/dev/vg_aiops/lv_rancher /var/lib/rancher xfs defaults,nofail 0 2" | tee -a /etc/fstab

echo "All specified Logical Volumes created, formatted, mounted, and added to fstab."
echo "LVM disk setup finished at $(date)"

# k3s won't run with nm-cloud-setup enabled
systemctl stop nm-cloud-setup.timer
systemctl disable nm-cloud-setup.timer 
systemctl stop nm-cloud-setup.service
systemctl disable nm-cloud-setup.service

%{ if mode == "extended" }
# allow SELinux users to execute files that have been modified, this
# is needed for extended installation, if this is not set then the
# aimanager-aio-cr-api pods will CrashLoop due to selinux
setsebool -P selinuxuser_execmod 1
%{ endif }

curl -LO "https://github.com/IBM/aiopsctl/releases/download/v${aiops_version}/aiopsctl-linux_amd64.tar.gz"
tar xf "aiopsctl-linux_amd64.tar.gz"
mv aiopsctl /usr/local/bin/aiopsctl

# Get the initial SELinux status
SELINUX_INITIAL_STATE=$(getenforce)
echo "Initial SELinux state is: $SELINUX_INITIAL_STATE"

# Check if SELinux is enforcing and disable it temporarily because RHEL 8.10 
# SELinux policy prevents cloud-init from adding firewall rules
if [ "$SELINUX_INITIAL_STATE" = "Enforcing" ]; then
    echo "Disabling SELinux temporarily to apply firewall rules."
    setenforce 0
else
    echo "SELinux is not in 'enforcing' mode. Skipping temporary disable."
fi

echo "Opening firewall ports"
firewall-cmd --permanent --add-port=8472/udp # Flannel VXLAN
firewall-cmd --permanent --add-port=51820/udp # Flannel + WireGuard (IPv4 traffic)
firewall-cmd --permanent --add-port=51821/udp # Flannel + WireGuard (IPv6 traffic)
firewall-cmd --permanent --add-port=10250/tcp # k3s kubelet metrics and logs (optional)
firewall-cmd --permanent --add-port=5001/tcp # Distributed registry
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services
firewall-cmd --reload
#systemctl stop firewalld
#systemctl disable firewalld

# Re-enable SELinux only if it was originally enforcing
if [ "$SELINUX_INITIAL_STATE" = "Enforcing" ]; then
    echo "Re-enabling SELinux."
    setenforce 1
else
    echo "SELinux was not in 'enforcing' mode. No changes made."
fi

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

aiopsctl cluster node up --server-url="https://${k3s_url}:6443" $INSTALL_PARAMS

# Check if SELinux is enforcing
if [ "$(getenforce)" == "Enforcing" ]; then
  echo "SELinux is in Enforcing mode. Restoring context to k3s so it can start."
  # Restore the context on the file after it's installed
  restorecon -v "/usr/local/bin/k3s"
else
  echo "SELinux is not in Enforcing mode. No action needed."
fi

disable_checksum_offload

nonroot_config
