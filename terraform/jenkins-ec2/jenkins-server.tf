resource "random_password" "jenkins_admin_password" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "jenkins_admin_password" {
  name  = "/jenkins/admin-password"
  type  = "SecureString"
  value = random_password.jenkins_admin_password.result
}

# https://registry.terraform.io/modules/terraform-aws-modules/key-pair/aws/2.0.2
module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "2.0.2"

  key_name           = "jenkins-server"
  create_private_key = true
  create             = true

}

resource "aws_ssm_parameter" "ssh_key_pem" {
  name  = "/jenkins/jenkins-private-key"
  type  = "SecureString"
  value = module.key_pair.private_key_pem
}

resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow Jenkins and SSH"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc.vpc_id

  ingress {
    description     = "Jenkins from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_alb_sg.id]
  }

  ingress {
    description = "Allow 8080 inside VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  ingress {
    description = "SSH to Jenkins"
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

resource "aws_instance" "jenkins_master" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = local.jenkins_subnet
  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  key_name               = "jenkins-server"
  iam_instance_profile   = aws_iam_instance_profile.jenkins_profile.name

  user_data = file("master-userdata.sh")

  tags = {
    Name              = "jenkins-master"
    terraform_managed = true
  }
}
