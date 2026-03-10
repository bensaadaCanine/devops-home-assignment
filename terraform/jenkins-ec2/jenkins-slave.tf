resource "aws_security_group" "jenkins_agent_sg" {
  name   = "jenkins-agent-sg"
  vpc_id = local.vpc_id

  ingress {
    from_port   = 50000
    to_port     = 50000
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "jenkins_agent" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = local.jenkins_subnet
  vpc_security_group_ids = [aws_security_group.jenkins_agent_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name
  key_name               = "jenkins-server"

  root_block_device {
    volume_size           = 15
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y java-21-amazon-corretto wget git awscli

              yum install -y docker
              systemctl enable docker
              systemctl start docker
              usermod -aG docker ec2-user

              curl -o /usr/local/bin/kubectl \
                https://s3.us-west-2.amazonaws.com/amazon-eks/1.27.0/2023-07-05/bin/linux/amd64/kubectl
              chmod +x /usr/local/bin/kubectl

              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

              mkdir -p /home/ec2-user/jenkins
              cd /home/ec2-user/jenkins

              mkdir -p /home/ec2-user/tmp
              chmod 1777 /home/ec2-user/tmp
              mount --bind /home/ec2-user/tmp /tmp
              echo '/home/ec2-user/tmp /tmp none bind 0 0' | tee -a /etc/fstab

              fallocate -l 2G /swapfile
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab

              JENKINS_MASTER_URL=${local.jenkins_master_url}
              AGENT_SECRET=${data.aws_ssm_parameter.jenkins_agent_secret.value}

              # Download Jenkins agent jar
              wget $JENKINS_MASTER_URL/jnlpJars/agent.jar

              java -jar agent.jar -url $JENKINS_MASTER_URL -secret $AGENT_SECRET -name "agent-1" -webSocket -workDir "/home/ec2-user/jenkins"
              EOF

  tags = {
    Name = "jenkins-agent"
  }
}
