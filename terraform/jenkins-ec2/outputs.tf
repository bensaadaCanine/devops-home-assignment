output "jenkins_iam_role" {
  value = aws_iam_role.jenkins_role
}

output "jenkins_agent_sg" {
  value = aws_security_group.jenkins_agent_sg
}

output "jenkins_url" {
  value = aws_lb.jenkins_alb
}

