data "terraform_remote_state" "jenkins" {
  backend = "s3"

  config = {
    bucket  = "bensaada-terraform-state"
    encrypt = true
    key     = "jenkins/terraform.tfstate"
    region  = "eu-west-1"
  }
}

data "aws_ssm_parameter" "jenkins_admin_password" {
  name            = "/jenkins/admin-password"
  with_decryption = true
}
