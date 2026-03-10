resource "aws_iam_role" "role" {
  name = var.role_name
  assume_role_policy = var.oidc_provider_bool ? jsonencode({
    Version = "2012-10-17",
    Statement = {
      Effect = "Allow",
      Principal = {
        Federated = "arn:aws:iam::${var.oidc_provider.account_id}:oidc-provider/${var.oidc_provider.url}"
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        "StringEquals" = {
          "${var.oidc_provider.url}:sub" = "system:serviceaccount:${var.oidc_provider.service_account_namespace}:${var.oidc_provider.service_account_name}"
          "${var.oidc_provider.url}:aud" = "sts.amazonaws.com"
        }
      }
    }
  }) : ""
}

resource "aws_iam_policy" "policy" {
  for_each    = { for policy in var.policies : policy.name => policy }
  name        = each.value.name
  description = each.value.description
  policy      = each.value.policy
  tags = {
    terraform_managed = true
  }
}

resource "aws_iam_role_policy_attachment" "policy_attach" {
  for_each   = { for policy in var.policies : policy.name => policy }
  role       = var.role_name
  policy_arn = aws_iam_policy.policy[each.key].arn
}
