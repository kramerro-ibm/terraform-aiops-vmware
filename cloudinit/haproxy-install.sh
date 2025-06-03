#!/bin/bash

set -x

# output in /var/log/cloud-init-output.log

# wait for subscription registration to complete
while ! subscription-manager status; do
    echo "Waiting for RHSM registration..."
    sleep 10
done

# install haproxy
yum install -y haproxy policycoreutils-python-utils

systemctl status haproxy

# add port to SELinux policy
semanage port -a -t http_cache_port_t -p tcp 6443
semanage permissive -a haproxy_t

echo "Opening firewall ports"
firewall-cmd --permanent --add-port=80/tcp # Application HTTP port
firewall-cmd --permanent --add-port=443/tcp # Application HTTPS port
firewall-cmd --permanent --add-port=6443/tcp # Control plane server API
firewall-cmd --reload

#
# vSphere govc CLI
#
curl -L https://github.com/vmware/govmomi/releases/latest/download/govc_Linux_x86_64.tar.gz | tar -C /usr/local/bin -xz
chmod +x /usr/local/bin/govc

export GOVC_URL=${vsphere_server}
export GOVC_USERNAME=${vsphere_user}
export GOVC_PASSWORD=${vsphere_password}
export GOVC_INSECURE=true

# get all 3 k3s server private IP addresses once they are running
private_ips=
while true; do
    private_ips=$(govc vm.info -json $(govc find /${vsphere_datacenter}/vm/${vsphere_folder} -type m -name 'k3s-server-*') | jq -r '.virtualMachines[] | select(.runtime.powerState == "poweredOn") | .guest.ipAddress' | grep -v '^null$')
    line_count=$(echo "$private_ips" | wc -l)
    
    if [ "$line_count" -eq 3 ]; then
        echo "$private_ips"
        break
    fi

    echo "Waiting for 3 k3s servers to be running"
    sleep 5
done

# Initialize an empty array
ip_array=()

# Read each line into the array
while IFS= read -r line; do
  ip_array+=("$line")
done <<< "$private_ips"

cat <<EOF > /etc/haproxy/haproxy.cfg
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    log         127.0.0.1 local2 debug

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

    # utilize system-wide crypto-policies
    ssl-default-bind-ciphers PROFILE=SYSTEM
    ssl-default-server-ciphers PROFILE=SYSTEM

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

frontend aiops-frontend
    bind *:443
    mode tcp
    option tcplog
    default_backend aiops-backend

backend aiops-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s
    server server-1  $${ip_array[0]}:443 check
    server server-2  $${ip_array[1]}:443 check
    server server-3  $${ip_array[2]}:443 check

frontend cncf-frontend
    bind *:6443
    mode tcp
    option tcplog
    default_backend cncf-backend

backend cncf-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s
    server server-1  $${ip_array[0]}:6443 check
    server server-2  $${ip_array[1]}:6443 check
    server server-3  $${ip_array[2]}:6443 check

frontend aiops-legacy-frontend
    bind *:80
    mode tcp
    option tcplog
    default_backend aiops-legacy-backend

backend aiops-legacy-backend
    mode tcp
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s
    server server-1  $${ip_array[0]}:80 check
    server server-2  $${ip_array[1]}:80 check
    server server-3  $${ip_array[2]}:80 check
EOF

#
# enable logging
#

# enable network tracking for rsyslog
sed -i 's/^#\(module(load="imtcp")\)/\1/' /etc/rsyslog.conf
sed -i 's/^#\(input(type="imtcp" port="514")\)/\1/' /etc/rsyslog.conf
sed -i 's/^#\(module(load="imudp")\)/\1/' /etc/rsyslog.conf
sed -i 's/^#\(input(type="imudp" port="514")\)/\1/' /etc/rsyslog.conf

# add a config file for logging
cat <<EOF > /etc/rsyslog.d/haproxy.conf
local2.* /var/log/haproxy.log
EOF

# allow non-root users to see logs
touch /var/log/haproxy.log
chmod 644 /var/log/haproxy.log

systemctl restart rsyslog

systemctl enable haproxy
systemctl start haproxy