provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      "eu-west-1"
    ]
  }
}

resource "aws_security_group_rule" "jenkins_to_eks" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = data.terraform_remote_state.jenkins.outputs.jenkins_agent_sg.id
}

resource "kubernetes_namespace_v1" "microservices" {
  depends_on = [
    module.eks
  ]

  metadata {
    name = "microservices"
  }
}

resource "kubernetes_role_v1" "jenkins" {
  depends_on = [
    module.eks
  ]

  metadata {
    name      = "jenkins"
    namespace = "microservices"
  }

  rule {
    api_groups = [""]
    resources  = ["serviceaccounts", "services", "configmaps", "pods", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["autoscaling"]
    resources  = ["horizontalpodautoscalers"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "jenkins" {
  depends_on = [
    module.eks
  ]

  metadata {
    name      = "jenkins-binding"
    namespace = "microservices"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "jenkins"
  }

  subject {
    kind      = "Group"
    name      = "jenkins"
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_role_v1" "jenkins_monitoring" {
  metadata {
    name      = "jenkins-monitoring-role"
    namespace = "monitoring"
  }

  rule {
    api_groups = ["monitoring.coreos.com"]
    resources  = ["servicemonitors"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "jenkins_monitoring" {
  metadata {
    name      = "jenkins-monitoring-rolebinding"
    namespace = "monitoring"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.jenkins_monitoring.metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "jenkins"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Safer than implemeting with EKS module
resource "aws_eks_access_entry" "jenkins" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = data.terraform_remote_state.jenkins.outputs.jenkins_iam_role.arn
  kubernetes_groups = ["jenkins"]

  depends_on = [module.eks]
}
