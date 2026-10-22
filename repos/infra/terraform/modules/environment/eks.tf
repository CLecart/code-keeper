module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  # Public API endpoint, restricted to the admin machine and the GitLab runner;
  # the nodes use the private one.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.eks_api_allowed_cidrs

  # The identity running Terraform (the CI role of the infra pipeline) becomes
  # cluster admin; the other identities come from access_entries below.
  enable_cluster_creator_admin_permissions = true

  # Every IAM role of the environment carries the boundary (see main.tf).
  iam_role_permissions_boundary = local.permissions_boundary

  # The pods get their AWS permissions through EKS Pod Identity, not IRSA.
  enable_irsa = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # No customer managed KMS key (1 USD/month, and a 7-day minimum deletion wait):
  # EKS already encrypts all Kubernetes API data by default since version 1.28.
  create_kms_key    = false
  encryption_config = null

  # Control plane logs in CloudWatch, kept one day only.
  enabled_log_types                      = ["api", "audit", "authenticator"]
  cloudwatch_log_group_retention_in_days = 1

  addons = {
    # enableNetworkPolicy: the VPC CNI enforces the NetworkPolicies of
    # platform/network-policies.yaml (eBPF agent in the aws-node DaemonSet).
    vpc-cni = {
      before_compute       = true
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    coredns                = {}
    # Resource metrics for the HorizontalPodAutoscalers.
    metrics-server = {}
    # Encrypted gp3 volumes for the databases and RabbitMQ.
    aws-ebs-csi-driver = {
      pod_identity_association = [{
        role_arn        = aws_iam_role.ebs_csi.arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    main = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      capacity_type  = "ON_DEMAND"

      min_size     = var.node_min_size
      desired_size = var.node_desired_size
      max_size     = var.node_max_size

      # Named after the environment like every other IAM role (see main.tf).
      iam_role_name                 = "${local.name}-nodes"
      iam_role_permissions_boundary = local.permissions_boundary
    }
  }

  access_entries = merge(
    # kubectl and terraform from the admin machine.
    {
      for index, arn in var.admin_principal_arns : "admin-${index}" => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    # Deployment jobs of each application (bootstrap/iam.tf of the code-keeper
    # repository): no EKS access policy, only a Kubernetes group. The Role bound
    # to that group (platform/rbac.yaml) covers the objects of the application
    # alone: never the databases, RabbitMQ, the Secrets or another application.
    {
      for app in var.applications : "ci-${app}" => {
        principal_arn     = "arn:aws:iam::${local.account_id}:role/${var.project}-ci-${app}"
        kubernetes_groups = ["${var.project}-deploy-${app}"]
      }
    },
  )
}

# Role assumed by the EBS CSI controller through EKS Pod Identity.
resource "aws_iam_role" "ebs_csi" {
  name                 = "${local.name}-ebs-csi"
  permissions_boundary = local.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
