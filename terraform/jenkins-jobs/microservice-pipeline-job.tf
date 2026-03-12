resource "jenkins_job" "microservices_pipeline" {
  name = "microservices-pipeline"

  template = templatefile("${path.module}/microservices-pipeline.xml", {
    repo_url = "https://github.com/bensaadaCanine/checkpoint-home-assignment.git"
    branch   = "master"
  })
}

# Read back the job that was just created
data "jenkins_job" "microservices_pipeline_verify" {
  name = jenkins_job.microservices_pipeline.name

  depends_on = [jenkins_job.microservices_pipeline]
}
