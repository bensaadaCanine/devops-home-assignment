#!/bin/bash
set -ex

# -------------------------
# Update system
# -------------------------
yum update -y

# -------------------------
# Add Jenkins repo and key file
# -------------------------
wget -O /etc/yum.repos.d/jenkins.repo \
  https://pkg.jenkins.io/rpm-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/rpm-stable/jenkins.io-2026.key
yum upgrade -y

# -------------------------
# Install dependencies
# -------------------------
yum install java-21-amazon-corretto git awscli -y

# -------------------------
# Install Jenkins
# -------------------------
yum install jenkins -y
systemctl enable jenkins

# -------------------------
# Retrieve admin user password from SSM
# -------------------------
export JENKINS_ADMIN_PASSWORD=$(aws ssm get-parameter \
  --name "/jenkins/admin-password" \
  --with-decryption \
  --region eu-west-1 \
  --query Parameter.Value \
  --output text)

# -------------------------
# Create admin user with groovy script
# -------------------------

mkdir -p /var/lib/jenkins/init.groovy.d

cat <<EOF >/var/lib/jenkins/init.groovy.d/basic-security.groovy
#!groovy

import jenkins.model.*
import hudson.security.*

def instance = Jenkins.getInstance()

def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("admin", "${JENKINS_ADMIN_PASSWORD}")
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)

instance.save()
EOF

# -------------------------
# Disable the setup wizard
# -------------------------
echo 'JENKINS_JAVA_OPTIONS="-Djenkins.install.runSetupWizard=false"' >>/etc/sysconfig/jenkins
echo "2.0" >/var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
echo "2.0" >/var/lib/jenkins/jenkins.install.UpgradeWizard.state

chown -R jenkins:jenkins /var/lib/jenkins
# -------------------------
# Jenkins start
# -------------------------
systemctl start jenkins
