# DevOps Home Assignment – EKS Microservices System

## Architecture

Client → ALB → Email Checker (MS) → SQS → Queue Checker (MS) → S3

Components:

- Amazon VPC
- Amazon EKS
- AWS Load Balancer Controller (ALB)
- Amazon SQS
- Amazon IAM
- Amazon S3
- Amazon EC2 Instances
- AWS SSM Parameter Store
- Amazon ECR
- Terraform
- Jenkins
- HELM

## Services

### Email Checker

REST API receiving POST requests and publishing validated payloads to SQS.

### Queue Checker

Worker that polls SQS and uploads messages to S3.

## Deployment Steps

### Prerequisites

- AWS CLI
- HELM
- kubectl

### 1. Deploy Infrastructure

Please change the CIDR block of the Jenkins ALB SG ingress before executing this code block. You can find it in `terraform/jenkins-ec2/alb.tf`. It mapped to my personal IP due to security reasons (Jenkins should be accessible to RnD teams only).

```sh
SERVICES=("remote-backend" "s3-buckets" "ssm" "sqs" "ecr" "vpc" "jenkins-ec2" "eks" "iam-roles" "jenkins-jobs")
cd terraform
for folder in $SERVICES; do
  cd $folder
  terraform init
  terraform apply
  cd ..
done
cd ..
```

#### Bonus

You can add/remove Jenkins agents by changing the local `jenkins_agents` inside `jenkins-ec2/data.tf`
and re-apply terraform for `jenkins-ec2` folder.

### 2. Configure kubectl

```sh
aws eks update-kubeconfig --region eu-west-1 \
  --name bensaada-home-assignment \
  --alias bensaada-home-assignment
```

### 3. Deploy ALB Controller In Kubernetes (HELM)

```sh
helm upgrade --install aws-load-balancer-controller \
  ./k8s-configuration/charts/aws-load-balancer-controller \
  -f ./k8s-configuration/charts/aws-load-balancer-controller/values.yaml \
  -n kube-system
```

### 4. Build The Microservices Job In Jenkins (For Both MS)

Execute the following command to get the DNS of Jenkins:

```sh
aws elbv2 describe-load-balancers --names 'jenkins-alb' \
  --query "LoadBalancers[0].DNSName" --output text
```

Execute the following command to get the admin user password:

```sh
aws ssm get-parameter --name '/jenkins/admin-password' --with-decryption \
  --query "Parameter.Value" --output text
```

#### IF JENKINS CAN'T DEPLOY TO KUBERNETES CLUSTER PLEASE TRY EXECUTE THE CODE BELOW AND RESTART YOUR JENKINS BUILD

```sh
cd ./terraform/eks
terraform apply -replace=aws_eks_access_entry.jenkins
```

### 5. Test API

```sh
EMAIL_CHECKER_DNS=$(kubectl get ingress email-checker -n microservices -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
TOKEN=$(aws ssm get-parameter --name '/email-checker/validation-token' --with-decryption --query "Parameter.Value" --output text)
curl -X POST "http://${EMAIL_CHECKER_DNS}/send" \
  -H "Content-Type: application/json" \
  -d '{"data":{"email_subject":"Happy new year!","email_sender":"John doe","email_timestream":"1693561101","email_content":"Just want to say... Happy new year!!!"},"token":"'"${TOKEN}"'"}'
```

### 6. BONUS: Deploy kube Prometheus Stack In Kubernetes (HELM)

```sh
GRAFANA_ADMIN_PASSWORD=$(aws ssm get-parameter --name '/grafana/admin-password' --with-decryption --query "Parameter.Value" --output text)
helm dependency build ./k8s-configuration/charts/kube-prom-stack
helm upgrade --install kube-prometheus-stack ./k8s-configuration/charts/kube-prom-stack \
  --namespace monitoring --create-namespace \
  -f ./k8s-configuration/charts/kube-prom-stack/values.yaml \
  -f ./k8s-configuration/values/kube-prom-stack.yaml \
  --set kube-prometheus-stack.grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}"
```

Get Grafana DNS from here:

```sh
kubectl get ingress kube-prometheus-stack-grafana \
  -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Get Prometheus DNS from here:

```sh
kubectl get ingress kube-prometheus-stack-prometheus \
  -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
<img width="1883" height="900" alt="image" src="https://github.com/user-attachments/assets/bd1e538a-a240-4f7a-b2ac-2af1d5e485ea" />

