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

```sh
SERVICES=("remote-backend" "s3-buckets" "ssm" "sqs" "ecr" "vpc" "jenkins-ec2" "eks" "iam-roles")
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

You can add/remove Jenkins agents by changing the local `jenkins_agents` inside `jenkins-ec2/data.tf` and re-apply terraform.

### 2. Configure kubectl

```sh
aws eks update-kubeconfig --region eu-west-1 \
  --name bensaada-home-assignment \
  --alias bensaada-home-assignment
```

### 3. Deploy ALB Controller In Kubernetes (HELM)

```sh
helm dependency build ./k8s-configuration/charts/aws-load-balancer-controller
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

### 5. Test API

```sh
EMAIL_CHECKER_DNS=$(kubectl get ingress email-checker -n microservices -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
TOKEN=$(aws ssm get-parameter --name '/email-checker/validation-token' --with-decryption --query "Parameter.Value" --output text)
curl -X POST "http://${EMAIL_CHECKER_DNS}/send" \
  -H "Content-Type: application/json" \
  -d '{"data":{"email_subject":"Happy new year!","email_sender":"John doe","email_timestream":"1693561101","email_content":"Just want to say... Happy new year!!!"},"token":"'"${TOKEN}"'"}'
```
