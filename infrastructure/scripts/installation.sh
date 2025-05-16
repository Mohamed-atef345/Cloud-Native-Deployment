#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status

sudo sed -i 's/^#\$nrconf{restart} = .*/$nrconf{restart} = '\''a'\'';/; s/^\$nrconf{restart} = .*/$nrconf{restart} = '\''a'\'';/' /etc/needrestart/needrestart.conf

# Create directories
mkdir -p ~/.local/bin

# Update system packages
sudo apt-get update
sudo apt-get upgrade -y

sleep 2

sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sleep 2

sudo apt-get install -y containerd

# Generate default configuration for containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl start containerd

sleep 2

echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Disable swap (required for Kubernetes)
sudo swapoff -a

# Install Kubernetes components
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.33/deb/Release.key | \
  gpg --dearmor | \
  sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sleep 2

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sleep 2

# Install Helm package manager
echo "Installing Helm..."
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm

sleep 2

# Initialize the Kubernetes cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=all

sleep 5

# Set up kubectl for current user
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

sleep 2


# Wait for Kubernetes API server to become ready
echo "Waiting for Kubernetes API server to respond to kubectl..."

for i in {1..20}; do
  if kubectl version --short &>/dev/null; then
    echo "Kubernetes API server is ready."
    break
  else
    echo "Waiting for API server... ($i/20)"
    sleep 5
  fi
done

# Untaint the master node so it can schedule pods
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

sleep 2

# Install Flannel network plugin
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

sleep 2

# Deploy ingress controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

sleep 1

kubectl rollout status deployment ingress-nginx-controller -n ingress-nginx --timeout=180s || true

sleep 2

helm install qrcode ./QRCode_APP_Chart   \
  --set-string Secret.DB_PASSWORD="$DB_PASSWORD"   \
  --set-string Secret.DB_HOST="$DB_HOST"   \
  --set-string Secret.DB_NAME="$DB_NAME"   \
  --set-string Secret.DB_USER="$DB_USER"   \
  --set-string Ingress.HostName="$URL" 

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.0.0/manifests/install.yaml

# Wait for Argo CD to be ready
echo "Waiting for Argo CD to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment/argocd-server -n argocd

wget https://github.com/argoproj/argo-cd/releases/download/v3.0.0/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd

echo "===== Exposing Argo CD API server via NodePort ====="
kubectl patch svc argocd-server -n argocd --type='merge' -p '{
  "spec": {
    "type": "NodePort",
    "ports": [
      {
        "port": 443,
        "targetPort": 8080,
        "nodePort": 30080,
        "protocol": "TCP",
        "name": "https"
      }
    ]
  }
}'

argocd login "$(curl -s http://checkip.amazonaws.com):30080" \
  --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)" \
  --insecure \
  --grpc-web
kubectl apply -f /home/ubuntu/argocd.yaml