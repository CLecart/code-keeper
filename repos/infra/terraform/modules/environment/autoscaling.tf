# Node autoscaling: AWS permissions of the Kubernetes Cluster Autoscaler (Helm
# chart installed by scripts/deploy-platform.sh, values in
# platform/helm/cluster-autoscaler.yaml).
#
# The autoscaler finds the node group through the tags EKS puts on its Auto
# Scaling group (k8s.io/cluster-autoscaler/enabled and .../<cluster>), adds a
# node when pods cannot be scheduled and removes an unneeded one, between
# node_min_size and node_max_size (eks.tf).

resource "aws_iam_role" "cluster_autoscaler" {
  name                 = "${local.name}-cluster-autoscaler"
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

# "Full Cluster Autoscaler Features Policy" of the autoscaler AWS documentation,
# with its two write actions restricted to the Auto Scaling groups of this cluster.
resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "scale-cluster-node-groups"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Discover"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeScalingActivities",
          "ec2:DescribeImages",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:GetInstanceTypesFromInstanceRequirements",
          "eks:DescribeNodegroup",
        ]
        Resource = "*"
      },
      {
        Sid      = "ScaleThisClusterOnly"
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:ResourceTag/k8s.io/cluster-autoscaler/${module.eks.cluster_name}" = "owned" }
        }
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "cluster_autoscaler" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "cluster-autoscaler"
  role_arn        = aws_iam_role.cluster_autoscaler.arn
}
