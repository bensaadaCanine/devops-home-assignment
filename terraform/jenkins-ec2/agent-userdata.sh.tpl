#!/bin/bash
yum update -y
yum install -y java-21-amazon-corretto wget git awscli docker jq python3 python3-pip
systemctl enable docker
systemctl start docker
usermod -aG docker ec2-user

curl -Lo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v1.27.0/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

pip3 install pytest requests boto3

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

mkdir -p /home/ec2-user/jenkins

# Injected by Terraform templatefile()
JENKINS_MASTER_URL="${jenkins_master_url}"
JENKINS_ADMIN_PASSWORD="${jenkins_admin_password}"

# Wait for Jenkins master to be ready
until curl -s -o /dev/null -w "%%{http_code}" \
  "$JENKINS_MASTER_URL/login" | grep -q "200"; do
  echo "Waiting for Jenkins master..."
  sleep 10
done

# Fetch crumb
CRUMB=$(curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" \
  "$JENKINS_MASTER_URL/crumbIssuer/api/json" \
  | jq -r '[.crumbRequestField, .crumb] | join(":")')

# Create agent node on Jenkins master
AGENT_JSON="{\"name\": \"${agent_name}\", \"nodeDescription\": \"EC2 agent\", \"numExecutors\": \"2\", \"remoteFS\": \"/home/ec2-user/jenkins\", \"labelString\": \"${agent_name}\", \"mode\": \"NORMAL\", \"retentionStrategy\": {\"stapler-class\": \"hudson.slaves.RetentionStrategy\$Always\"}, \"nodeProperties\": {\"stapler-class-bag\": \"true\"}, \"launcher\": {\"stapler-class\": \"hudson.slaves.JNLPLauncher\", \"webSocket\": true}}"

curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" \
  -H "$CRUMB" \
  -X POST "$JENKINS_MASTER_URL/computer/doCreateItem?name=${agent_name}&type=hudson.slaves.DumbSlave" \
  --data-urlencode "json=$AGENT_JSON"

# Fetch the agent secret Jenkins generated for the agent
AGENT_SECRET=$(curl -s -u "admin:$JENKINS_ADMIN_PASSWORD" \
  -H "$CRUMB" \
  "$JENKINS_MASTER_URL/computer/${agent_name}/slave-agent.jnlp" \
  | grep -oP '(?<=<argument>)[a-f0-9]{64}(?=</argument>)')

# Download Jenkins agent jar
wget -O /home/ec2-user/jenkins/agent.jar \
  "$JENKINS_MASTER_URL/jnlpJars/agent.jar"

java -jar agent.jar -url $JENKINS_MASTER_URL -secret $AGENT_SECRET -name "${agent_name}" -webSocket -workDir "/home/ec2-user/jenkins"
