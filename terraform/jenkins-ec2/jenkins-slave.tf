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
  for_each               = toset(local.jenkins_agents)
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

  user_data = templatefile("${path.module}/templates/jenkins_agent_userdata.sh", {
    jenkins_master_url     = local.jenkins_master_url
    jenkins_admin_password = random_password.jenkins_admin_password.result
    agent_name             = each.value
  })

  tags = {
    Name = "jenkins-agent-${each.value}"
  }
}
