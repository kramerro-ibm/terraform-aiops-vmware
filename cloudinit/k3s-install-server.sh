#!/bin/bash

set -x

# output in /var/log/cloud-init-output.log

install_aiops=${install_aiops}
num_nodes=${num_nodes}

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
chmod 660 /etc/rancher/k3s/k3s.yaml

# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/
chmod 750 /var/lib/rancher/k3s/agent/etc/
# for crictl
chown root:k3sadmin /var/lib/rancher/k3s/agent/etc/crictl.yaml
chmod 640 /var/lib/rancher/k3s/agent/etc/crictl.yaml

%{ if !use_private_registry }
# for oc
mkdir -p /home/clouduser/.kube
cp /etc/rancher/k3s/k3s.yaml /home/clouduser/.kube/config
chown -R clouduser:clouduser /home/clouduser/.kube
%{ endif }
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

# echo "Disabling selinux"
# sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
# setenforce 0
echo "Opening firewall ports"
firewall-cmd --permanent --add-port=80/tcp # Application HTTP port
firewall-cmd --permanent --add-port=443/tcp # Application HTTPS port
firewall-cmd --permanent --add-port=6443/tcp # Control plane server API
firewall-cmd --permanent --add-port=8472/udp # Virtual network
firewall-cmd --permanent --add-port=10250/tcp # k3s Kubelet metrics and logs (optional)
firewall-cmd --permanent --add-port=2379/tcp # k3s etcd client communication
firewall-cmd --permanent --add-port=2380/tcp # k3s etcd peer communication
firewall-cmd --permanent --add-port=51820/udp # Flannel + WireGuard (IPv4 traffic)
firewall-cmd --permanent --add-port=51821/udp # Flannel + WireGuard (IPv6 traffic)
firewall-cmd --permanent --add-port=5001/tcp # Distributed registry
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16 # pods
firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16 # services
firewall-cmd --reload

yum -y install bind-utils

first_instance="k3s-server-0.${base_domain}"
instance_id=$(hostname)

# this is not being set automatically
export HOME=/root

k3s_install_params=("--accept-license=${accept_license}")
k3s_install_params+=("--role=control-plane")
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
k3s_install_params+=("--platform-storage /var/lib/aiops/platform")
k3s_install_params+=("--image-storage /var/lib/aiops/storage")
k3s_install_params+=("--load-balancer-host=${k3s_url}")
%{ if ignore_prereqs } 
k3s_install_params+=("--force")
%{ endif }

INSTALL_PARAMS="$${k3s_install_params[*]}"

if [[ "$first_instance" == "$instance_id" ]]; then
  echo "Happy, happy, joy, joy: Cluster init!"
  until (aiopsctl cluster node up $INSTALL_PARAMS); do
    echo 'k3s did not install correctly'
    sleep 2
  done

  disable_checksum_offload

  nonroot_config

  # wait for k3s startup
  until kubectl get pods -A | grep 'Running'; do
    echo 'Waiting for k3s startup'
    sleep 5
  done

  # Loop until all nodes are registered
  while true; do
    node_count=$(kubectl get nodes | tail -n +2 | wc -l)
    if [ "$node_count" -eq "$num_nodes" ]; then
      echo "Node count is $num_nodes - Exiting loop."
      break
    else
      echo "Current node count is $node_count. Waiting..."
      sleep 10  # Wait for 10 seconds before checking again
    fi
  done

  # update coredns for haproxy resolution
  kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns-custom
  namespace: kube-system
data:
  default.server: |
    cp-console-aiops.${k3s_url} {
        hosts {
              192.168.252.9 cp-console-aiops.${k3s_url}
              fallthrough
        }
    }
    aiops-cpd.${k3s_url} {
        hosts {
              192.168.252.9 aiops-cpd.${k3s_url}
              fallthrough
        }
    }
EOF
  kubectl -n kube-system rollout restart deployment coredns

  # additional sleep to make sure all nodes are up
  sleep 10

  # install aiops
  if [[ "$install_aiops" == "true" ]]; then
    aiopsctl server up --load-balancer-host="${k3s_url}" --mode "${mode}" --force
  fi

else
  echo ":( Cluster join"
  wait_lb
  sleep 5
  until (aiopsctl cluster node up --server-url="https://$first_instance:6443" $INSTALL_PARAMS); do
    echo 'k3s did not install correctly'
    sleep 5
  done

  disable_checksum_offload

  nonroot_config
fi