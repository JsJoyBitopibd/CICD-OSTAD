#!/usr/bin/env bash
# ---------------------------------------------------------------
# 02-init-cluster.sh
# Turns this single EC2 instance into a working Kubernetes cluster.
# Run AFTER 01-install-k8s.sh.
# Author : Joyanta Sarker Joy - Mastering DevOps Batch 13
# ---------------------------------------------------------------
set -euo pipefail

# The instance's own addresses. PRIVATE_IP is what the cluster talks on;
# PUBLIC_IP is only added to the API server certificate so that kubectl
# can also be used from a laptop outside AWS.
PRIVATE_IP="$(hostname -I | awk '{print $1}')"
PUBLIC_IP="$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 || echo '')"
echo "Private IP : $PRIVATE_IP"
echo "Public  IP : $PUBLIC_IP"

echo "=============================================="
echo " [1/5] kubeadm init - creating the control plane"
echo "=============================================="
# --pod-network-cidr MUST match what the CNI plugin expects.
# Flannel's default manifest uses 10.244.0.0/16.
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address="${PRIVATE_IP}" \
  ${PUBLIC_IP:+--apiserver-cert-extra-sans="${PUBLIC_IP}"} \
  | tee "$HOME/kubeadm-init.log"

echo "=============================================="
echo " [2/5] Giving the ubuntu user a kubeconfig"
echo "=============================================="
# admin.conf holds the cluster address plus the admin certificate.
# kubectl reads ~/.kube/config by default, so we copy it there.
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
kubectl get nodes

echo "=============================================="
echo " [3/5] Installing Flannel (the pod network)"
echo "=============================================="
# Without a CNI plugin the node stays NotReady and CoreDNS stays Pending,
# because pods have no way to get an IP address.
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

echo "=============================================="
echo " [4/5] Allowing normal pods on the control-plane node"
echo "=============================================="
# kubeadm taints the control plane so ordinary workloads stay off it.
# On a single-node cluster that would mean nothing can ever be scheduled,
# so the taint has to be removed.
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- || true

echo "=============================================="
echo " [5/5] Waiting for the node to become Ready"
echo "=============================================="
kubectl wait --for=condition=Ready node --all --timeout=180s || true
echo ""
echo "--- Nodes ---"
kubectl get nodes -o wide
echo ""
echo "--- System pods ---"
kubectl get pods -n kube-system
echo ""
echo "Cluster is up. Next step: create the production namespace."
