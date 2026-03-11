terraform {
  backend "s3" {
    bucket         = "bensaada-terraform-state"
    key            = "jenkins_jobs/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}
