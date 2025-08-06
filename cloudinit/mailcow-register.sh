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