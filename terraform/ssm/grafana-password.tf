resource "random_password" "grafana_pass" {
  length  = 16
  special = false
}

resource "aws_ssm_parameter" "grafana_pass" {
  name  = "/grafana/admin-password"
  type  = "SecureString"
  value = random_password.validation_token.result
}
