terraform {
  required_providers {
    jenkins = {
      source  = "taiidani/jenkins"
      version = "~> 0.10"
    }
  }
}

provider "jenkins" {
  server_url = "http://${aws_lb.jenkins_alb.dns_name}"
  username   = "admin"
  password   = random_password.jenkins_admin_password.result
}

resource "jenkins_job" "microservices_pipeline" {
  name = "microservices-pipeline"

  template = templatefile("${path.module}/microservices-pipeline.xml", {
    repo_url = "https://github.com/bensaadaCanine/checkpoint-home-assignment.git"
    branch   = "master"
  })
}
