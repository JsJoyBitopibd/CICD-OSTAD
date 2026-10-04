# Dockerize → Docker Hub → Kubernetes on AWS EC2

Module 12 assignment — **Mastering DevOps, Batch 13**
Author: **Joyanta Sarker Joy**

This repository contains everything needed to containerise the Node.js/Express
application in `src/` and run it on a single-node Kubernetes cluster built with
`kubeadm` on an AWS EC2 instance.

## Links

| Item | Value |
|---|---|
| Docker Hub image | https://hub.docker.com/r/joyantasarkerjoy/cicd-ostad |
| Image tags | `joyantasarkerjoy/cicd-ostad:1.0`, `:latest` |
| Cluster | 1 × AWS EC2 `t3.small`, Ubuntu 24.04 LTS, ap-south-1 |
| Kubernetes | v1.37.1 (kubeadm) + containerd 2.3.6 + Flannel CNI |
| Namespace | `production` |
| Exposure | NodePort `30080` |

## Files added for this assignment

```
Dockerfile                  Image recipe (node:20-alpine, non-root, healthcheck)
.dockerignore               Keeps node_modules/.git out of the build context
k8s/namespace.yaml          The production namespace
k8s/deployment.yaml         2 replicas, probes, resource requests/limits
k8s/service.yaml            NodePort service, 80 -> 4000, nodePort 30080
scripts/01-install-k8s.sh   containerd + kubeadm/kubelet/kubectl on Ubuntu
scripts/02-init-cluster.sh  kubeadm init + kubeconfig + Flannel + untaint
```

## Quick start

### 1. Build and test locally

```bash
docker build -t cicd-ostad:1.0 ./
docker run -d --name cicd-test -p 4000:4000 cicd-ostad:1.0
curl http://localhost:4000/api          # {"message":"Hello World"}
docker rm -f cicd-test
```

### 2. Publish to Docker Hub

```bash
docker login
docker tag cicd-ostad:1.0 joyantasarkerjoy/cicd-ostad:1.0
docker tag cicd-ostad:1.0 joyantasarkerjoy/cicd-ostad:latest
docker push joyantasarkerjoy/cicd-ostad:1.0
docker push joyantasarkerjoy/cicd-ostad:latest
```

### 3. Build the cluster on the EC2

Security group inbound: `22` (SSH), `6443` (API server), `30000-32767` (NodePort).

```bash
ssh -i ostad-k8s-key.pem ubuntu@<EC2_PUBLIC_IP>
bash scripts/01-install-k8s.sh
bash scripts/02-init-cluster.sh
kubectl get nodes          # expect: Ready
```

### 4. Deploy

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl rollout status deployment/cicd-ostad -n production
kubectl get all -n production
```

### 5. Verify

```bash
curl http://<EC2_PUBLIC_IP>:30080/api    # {"message":"Hello World"}
```

Open `http://<EC2_PUBLIC_IP>:30080` in a browser for the web page.

## How traffic flows

```
Browser  ->  EC2 public IP : 30080        (NodePort, opened in the security group)
         ->  kube-proxy iptables rules    (on the node)
         ->  Service cicd-ostad-svc :80   (ClusterIP 10.110.239.157)
         ->  Pod :4000                    (10.244.0.4 or 10.244.0.5, chosen per connection)
```

Pod-to-pod traffic never uses IP addresses directly. A pod calls
`http://cicd-ostad-svc/api`; CoreDNS (10.96.0.10) resolves the name using the
search domains in `/etc/resolv.conf`, and kube-proxy rewrites the destination to
one of the healthy pod IPs listed in the Service's Endpoints.

## Cleanup

```bash
kubectl delete -f k8s/service.yaml -f k8s/deployment.yaml -f k8s/namespace.yaml
# then Terminate the EC2 instance in the AWS console
```
