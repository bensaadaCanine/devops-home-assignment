terraform {
  required_providers {
    jenkins = {
      source  = "taiidani/jenkins"
      version = "~> 0.10"
    }
  }
}

provider "jenkins" {
  server_url = "http://${data.terraform_remote_state.jenkins.outputs.jenkins_url.dns_name}"
  username   = "admin"
  password   = data.aws_ssm_parameter.jenkins_admin_password.value
}
