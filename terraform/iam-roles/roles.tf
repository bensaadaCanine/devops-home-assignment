locals {
  roles = [
    {
      role_name = "email-checker-role"
      policies = [
        {
          name = "email-checker-policies"
          policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect   = "Allow"
                Action   = "ssm:Get*"
                Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/email-checker*"
              },
              {
                Effect = "Allow"
                Action : [
                  "sqs:SendMessage",
                  "sqs:GetQueueUrl",
                  "sqs:GetQueueAttributes"
                ],
                Resource = data.terraform_remote_state.sqs.outputs.emails_queue.arn
              }

            ]
          })
        }
      ]
      oidc_provider_bool = true
      oidc_provider = {
        url                       = local.eks_oidc_provider
        account_id                = data.aws_caller_identity.current.account_id
        service_account_name      = "email-checker"
        service_account_namespace = "microservices"
      }
    },
    {
      role_name = "queue-checker-role"
      policies = [
        {
          name = "queue-checker-policies"
          policy = jsonencode({
            Version = "2012-10-17"
            Statement = [
              {
                Effect = "Allow"
                Action = [
                  "s3:ListBucket",
                  "s3:GetBucketLocation",
                  "s3:PutObject",
                  "s3:PutObjectAcl"
                ]
                Resource = [
                  data.terraform_remote_state.s3.outputs.emails_bucket.arn,
                  "${data.terraform_remote_state.s3.outputs.emails_bucket.arn}/*"
                ]
              },
              {
                Effect = "Allow"
                Action : [
                  "sqs:ReceiveMessage",
                  "sqs:DeleteMessage",
                  "sqs:GetQueueUrl",
                  "sqs:GetQueueAttributes",
                  "sqs:ChangeMessageVisibility"
                ],
                Resource = data.terraform_remote_state.sqs.outputs.emails_queue.arn
              }
            ]
          })
        }
      ]
      oidc_provider_bool = true
      oidc_provider = {
        url                       = local.eks_oidc_provider
        account_id                = data.aws_caller_identity.current.account_id
        service_account_name      = "queue-checker"
        service_account_namespace = "microservices"
      }
    },
    {
      role_name = "aws-load-balancer-controller-role"
      policies = [
        {
          name   = "aws-load-balancer-controller-policies"
          policy = data.http.alb_controller_policies.response_body
        }
      ]
      oidc_provider_bool = true
      oidc_provider = {
        url                       = local.eks_oidc_provider
        account_id                = data.aws_caller_identity.current.account_id
        service_account_name      = "aws-load-balancer-controller"
        service_account_namespace = "kube-system"
      }
    },
  ]
}
