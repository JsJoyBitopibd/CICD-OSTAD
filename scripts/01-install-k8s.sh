#!/usr/bin/env bash
# ---------------------------------------------------------------
# 01-install-k8s.sh
# Prepares a fresh Ubuntu 24.04 EC2 instance to be a Kubernetes node.
# Installs: containerd (CRI runtime) + kubeadm + kubelet + kubectl
# Author : Joyanta Sarker Joy - Mastering DevOps Batch 13
# Usage  : bash 01-install-k8s.sh
# ---------------------------------------------------------------
set -euo pipefail

echo "=============================================="
echo " [1/6] Turning swap OFF"
echo "=============================================="
# The kubelet refuses to start while swap is on, because Kubernetes
# schedules pods by real RAM. Swap would make memory limits meaningless.
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
free -h

echo "=============================================="
echo " [2/6] Loading kernel modules and network settings"
echo "=============================================="
# overlay      -> the filesystem containerd uses to stack image layers
# br_netfilter -> lets iptables see traffic crossing the Linux bridge,
#                 which is how Service/NetworkPolicy rules are enforced
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

# ip_forward=1 lets the node route packets between pods.
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null
echo "Kernel settings applied."

echo "=============================================="
echo " [3/6] Installing containerd (the container runtime)"
echo "=============================================="
# Kubernetes removed Docker support in v1.24. containerd is the engine
# that actually pulls images and runs containers; Docker uses it too.
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg apt-transport-https
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y containerd.io

echo "=============================================="
echo " [4/6] Pointing containerd at the systemd cgroup driver"
echo "=============================================="
# kubelet and containerd MUST use the same cgroup driver or the node
# goes NotReady. Ubuntu uses systemd, so containerd must too.
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
grep -n "SystemdCgroup" /etc/containerd/config.toml || true

echo "=============================================="
echo " [5/6] Installing kubeadm, kubelet and kubectl"
echo "=============================================="
# Ask Kubernetes itself which release is current, instead of hard-coding
# a version that may be gone by the time this script is run again.
KREL="$(curl -sL https://dl.k8s.io/release/stable.txt)"
KMINOR="$(echo "$KREL" | cut -d. -f1,2)"
echo "Latest stable Kubernetes release : $KREL"
echo "Package repository channel       : $KMINOR"

if ! curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KMINOR}/deb/Release.key" -o /tmp/k8s.key; then
  MAJ="$(echo "$KMINOR" | cut -d. -f1)"
  MIN="$(echo "$KMINOR" | cut -d. -f2)"
  KMINOR="${MAJ}.$((MIN-1))"
  echo "That channel is not published yet - falling back to ${KMINOR}"
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/${KMINOR}/deb/Release.key" -o /tmp/k8s.key
fi

sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg < /tmp/k8s.key
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${KMINOR}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# "hold" freezes these three packages. An accidental apt upgrade that
# bumps the kubelet out of step with the control plane breaks the node.
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

echo "=============================================="
echo " [6/6] Verification"
echo "=============================================="
echo "--- containerd ---" && containerd --version
echo "--- kubeadm   ---" && kubeadm version -o short
echo "--- kubectl   ---" && kubectl version --client | head -2
echo "--- kubelet   ---" && kubelet --version
echo "--- resources ---" && echo "CPUs: $(nproc)" && free -h
echo ""
echo "Installation complete. Next step: kubeadm init."
