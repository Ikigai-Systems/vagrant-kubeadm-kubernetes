#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Check if /vagrant is correctly mounted through NFS
if ! mount | grep -q 'on /vagrant type nfs'; then
  echo "/vagrant is not mounted through NFS, check your firewall settings"
  exit 1
fi

# Variable Declaration

# DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

systemctl restart systemd-resolved

# disable swap
swapoff -a

# keeps the swap off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
apt-get update -y


# Create the .conf file to load the modules at bootup
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# sysctl params required by setup, params persist across reboots
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sysctl --system

apt-get update -y
apt-get install -y software-properties-common curl apt-transport-https ca-certificates

if [ "$CRI" = "cri-o" ]; then
  ## Install CRIO Runtime

  curl -fsSL https://pkgs.k8s.io/addons:/cri-o:/stable:/v$CRI_VERSION_SHORT/deb/Release.key |
      gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg

  echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://pkgs.k8s.io/addons:/cri-o:/stable:/v$CRI_VERSION_SHORT/deb/ /" |
      tee /etc/apt/sources.list.d/cri-o.list

  apt-get update -y
  apt-get install -y cri-o="$CRI_VERSION"

  systemctl daemon-reload
  systemctl enable crio --now
  systemctl start crio.service

  apt-mark hold cri-o

  echo "CRI-O runtime installed successfully"
fi

if [ "$CRI" = "containerd" ]; then
  ## Install containerd Runtime

  curl -fsSL https://download.docker.com/linux/ubuntu/gpg |
      gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" |
      tee /etc/apt/sources.list.d/docker.list

  # Update and install containerd
  apt-get update -y
  apt-get install -y containerd.io

  mkdir -p /etc/containerd
  containerd config default > /etc/containerd/config.toml

  systemctl daemon-reload
  systemctl enable containerd --now
  systemctl start containerd

  apt-mark hold containerd.io

  echo "containerd runtime installed successfully"
fi

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION_SHORT/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION_SHORT/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list


apt-get update -y
apt-get install -y kubelet="$KUBERNETES_VERSION" kubectl="$KUBERNETES_VERSION" kubeadm="$KUBERNETES_VERSION"
apt-get update -y
apt-get install -y jq

# Disable auto-update services
apt-mark hold kubelet kubectl kubeadm

local_ip="$(ip --json a s | jq -r '.[] | select(.ifname == "eth1") | .addr_info[] | select(.family == "inet") | .local')"

mkdir -p /etc/kubernetes/kubelet.conf.d
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS="--node-ip=$local_ip --config-dir=/etc/kubernetes/kubelet.conf.d"
${ENVIRONMENT}
EOF
