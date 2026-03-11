locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc.vpc_id
  vpc_cidr_block     = data.terraform_remote_state.vpc.outputs.vpc.vpc_cidr_block
  jenkins_subnet     = data.terraform_remote_state.vpc.outputs.vpc.private_subnets[0]
  jenkins_master_url = "http://${aws_instance.jenkins_master.private_ip}:8080"
  jenkins_agents = [
    "agent-1"
  ]
}
data "terraform_remote_state" "vpc" {
  backend = "s3"

  config = {
    bucket  = "bensaada-terraform-state"
    encrypt = true
    key     = "vpc/terraform.tfstate"
    region  = "eu-west-1"
  }
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
