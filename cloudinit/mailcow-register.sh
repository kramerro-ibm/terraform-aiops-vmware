#!/bin/bash

set -x

# output in /var/log/cloud-init-output.log

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

echo "Starting LVM disk for docker setup at $(date)"

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

# We don't need no fancy separate volume group for docker. Let's just extend rootvg
if [ -n "$processed_disks" ]; then
  vgextend rhel $processed_disks
  lvextend -l 100%VG rhel/root
  xfs_growfs /
else
  echo "No disks were processed."
fi

echo "LVM disk setup for docker finished at $(date)"