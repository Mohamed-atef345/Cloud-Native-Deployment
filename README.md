# Cloud-Native-Deployment

This repository contains the complete infrastructure setup for deploying a containerized application on AWS using Terraform, Kubernetes (`kubeadm`), Helm, and Argo CD. It follows Infrastructure-as-Code and GitOps best practices to ensure scalable, secure, and automated deployments.

---

## 🔧 Tech Stack

* **Infrastructure as Code:** Terraform  
* **Configuration Management:** AWS SSM Parameter Store  
* **Containerization:** Containerd  
* **Orchestration:** Kubernetes (`kubeadm`)  
* **CI/CD & GitOps:** Helm, Argo CD  
* **Cloud Provider:** AWS  

---

## ☁️ Infrastructure Overview

### AWS Components Provisioned via Terraform:

* **VPC** with:

  * Public and private subnets  
  * Internet Gateway  
  * Route Tables and Associations  

* **Security Groups**:

  * `web_sg`: Allows access on ports 22 (SSH), 80 (HTTP), 6443 (Kubernetes API), and 30080 (NodePort)  
  * `db_sg`: Allows access to port 1433 (SQL Server) from the `web_sg` only  

* **Key Pair** for EC2 access  

* **EC2 Instance**:

  * Hosts a Kubernetes cluster initialized using `kubeadm`  
  * Runs a setup script to install and configure:  
    * Containerd  
    * kubeadm, kubelet, kubectl  
    * Helm  
    * Argo CD  

* **RDS Instance**:

  * Engine: SQL Server Express  
  * Private subnet, not publicly accessible  

* **AWS SSM Parameters** (used for secure configuration):

  * `/Cloud-Deployment/dbuser`  
  * `/Cloud-Deployment/dbpass`  
  * `/Cloud-Deployment/dbname`  

---

## 🛠️ Deployment Steps

### 1. Provision Infrastructure with Terraform

```bash
cd infra
terraform init
terraform apply
````

This command provisions all AWS resources including VPC, EC2, RDS, Security Groups, and SSM parameters.
**The EC2 instance automatically runs the setup script during provisioning, installing Docker, Kubernetes components, Helm, and Argo CD.**

---

### 2. Connect to EC2 Instance (optional)

You can connect to the EC2 instance if needed:

```bash
ssh -i <your-key.pem> ubuntu@<public-ip>
```

---

### 3. Access Argo CD Dashboard

Argo CD is exposed via **NodePort 30080** on the EC2 instance's public IP. Access it in your browser:

```
https://<public-ip>:30080
```

Default login:

* **Username:** `admin`
* **Password:**

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

### 4. Deploy Argo CD Application

```bash
kubectl apply -f infra/scripts/argocd.yaml
```

This creates an Argo CD Application that pulls and deploys the Helm chart from the `Cloud-Deployment/app-chart/` directory.

---


## 🧠 Notes

* All infrastructure resources and the setup script execution are managed and triggered automatically by Terraform in the `infra/` directory.
* Helm charts are stored in `Cloud-Deployment/app-chart/`.
* Argo CD is exposed on **NodePort 30080** and is always available at `https://<public-ip>:30080`.
* The RDS instance is secured in a private subnet and only accessible by the EC2 instance.
* Secrets are securely managed via AWS SSM Parameter Store and injected into Kubernetes.
