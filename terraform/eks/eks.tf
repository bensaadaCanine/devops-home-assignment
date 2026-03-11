# https://registry.terraform.io/modules/terraform-aws-modules/key-pair/aws/2.0.2
module "key_pair" {
  source  = "terraform-aws-modules/key-pair/aws"
  version = "2.0.2"

  key_name           = local.cluster_name
  create_private_key = true
  create             = true

}

resource "aws_ssm_parameter" "ssh_key_pem" {
  name  = "/eks/${local.cluster_name}-private-key"
  type  = "SecureString"
  value = module.key_pair.private_key_pem
}

# https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/20.37.2
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  # In a real production oriented environment I wouldn't have done this.
  # I would create a VPC for a VPN and allow private access only through its CIDR.
  cluster_endpoint_public_access = true

  enable_cluster_creator_admin_permissions = true

  access_entries = {
    jenkins = {
      principal_arn     = data.terraform_remote_state.jenkins.outputs.jenkins_iam_role.arn
      kubernetes_groups = ["jenkins"]
      type              = "STANDARD"
    }
  }

  # Network
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc.vpc_id
  subnet_ids  = data.terraform_remote_state.vpc.outputs.vpc.private_subnets
  enable_irsa = true

  # Addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  # EKS Managed Node Group
  eks_managed_node_groups = {
    default = {
      instance_types               = ["t3.micro"] # Free tier instance types
      min_size                     = 2
      max_size                     = 50
      desired_size                 = 5
      iam_role_additional_policies = local.iam_role_additional_policies

      # Ref https://awslabs.github.io/amazon-eks-ami/nodeadm/doc/api/
      cloudinit_pre_nodeadm = [
        {
          content_type = "application/node.eks.aws"
          content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  shutdownGracePeriod: 30s
                  featureGates:
                    DisableKubeletCloudCredentialProviders: true
          EOT
        }
      ]
    }
  }

  tags = local.default_cluster_tags
}
