# One IAM role per GitLab project, assumed through OIDC (oidc.tf). The trust
# policy only accepts the ID token of that project on its protected main
# branch: a job of another branch or another project gets nothing.
#
#   code-keeper-ci-infra            Terraform of the environments (infra repository)
#   code-keeper-ci-<application>    push of its own image, access to the clusters

locals {
  ci_projects = concat(["infra"], var.applications)

  # Every resource of an environment is named code-keeper-<environment>-...;
  # the infra role may only manage IAM roles with these prefixes, never the
  # CI roles below, and each of them must carry the environment boundary.
  environment_prefixes = [for env in var.environments : "${var.project}-${env}"]
  environment_roles    = [for prefix in local.environment_prefixes : "arn:aws:iam::${local.account_id}:role/${prefix}-*"]
  environment_clusters = [for prefix in local.environment_prefixes : "arn:aws:eks:${var.region}:${local.account_id}:cluster/${prefix}"]

  # AWS managed policies the EKS module and the environment attach to their roles.
  environment_managed_policies = [
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy",
  ]

  platform_images = setsubtract(var.images, var.applications)
}

data "aws_iam_policy_document" "ci_trust" {
  for_each = toset(local.ci_projects)

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = [local.oidc_audience]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["project_path:${var.gitlab_group}/${each.key}:ref_type:branch:ref:main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each = toset(local.ci_projects)

  name                 = "${var.project}-ci-${each.key}"
  description          = "GitLab CI of ${var.gitlab_group}/${each.key}, main branch only"
  assume_role_policy   = data.aws_iam_policy_document.ci_trust[each.key].json
  max_session_duration = 3600
}

# ---- the tooling stack is out of reach -----------------------------------------

# Every resource of this stack carries Stack=bootstrap (provider default_tags).
# The CI roles and the roles they create may never act on its EC2 resources:
# GitLab, the runner, their disks, network and firewall. Describe calls carry
# no resource tag, so they keep working.
data "aws_iam_policy_document" "deny_tooling" {
  statement {
    sid       = "NeverTouchTheToolingStack"
    effect    = "Deny"
    actions   = ["ec2:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/Stack"
      values   = ["bootstrap"]
    }
  }
}

# ---- boundary of every role created by the infra pipeline ----------------------

# The infra role may only create a role that carries this boundary: whatever
# policies the role receives, its rights never exceed what the cluster, its
# nodes, the EBS driver, the autoscaler and Fluent Bit need. No IAM (except
# service-linked roles), no STS, nothing outside Paris-side compute and logs.
data "aws_iam_policy_document" "environment_boundary" {
  source_policy_documents = [data.aws_iam_policy_document.deny_tooling.json]

  statement {
    sid = "EnvironmentWorkloads"
    actions = [
      "autoscaling:*",
      "ec2:*",
      "eks-auth:AssumeRoleForPodIdentity",
      "eks:*",
      "elasticloadbalancing:*",
      "logs:*",
    ]
    resources = ["*"]
  }

  statement {
    sid = "PullImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:Describe*",
      "ecr:Get*",
      "ecr:List*",
    ]
    resources = ["*"]
  }

  # Encrypted EBS volumes (AWS managed key, through EC2 only).
  statement {
    sid = "EncryptedVolumes"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "environment_boundary" {
  name        = "${var.project}-environment-boundary"
  description = "Upper limit of the rights of every IAM role created by the infra pipeline"
  policy      = data.aws_iam_policy_document.environment_boundary.json
}

# ---- infra: Terraform of the staging and production environments -----------

data "aws_iam_policy_document" "ci_infra" {
  source_policy_documents = [data.aws_iam_policy_document.deny_tooling.json]

  # The AWS services of an environment (cloud-design architecture), in Paris only.
  statement {
    sid = "EnvironmentServicesInParis"
    actions = [
      "apigateway:*",
      "autoscaling:*",
      "cloudwatch:*",
      "cognito-idp:*",
      "ec2:*",
      "eks:*",
      "elasticloadbalancing:*",
      "logs:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # Version of the EKS optimized AMI, read by the node group module at plan time.
  statement {
    sid       = "EksPublicParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = ["arn:aws:ssm:${var.region}::parameter/aws/service/eks/*"]
  }

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # Creating or changing the policies of an environment role requires the
  # boundary on that role (AWS example "CreateOrChangeOnlyWithBoundary"), and
  # only the managed policies the environment uses can be attached.
  # PutRolePermissionsBoundary and DeleteRolePermissionsBoundary are never granted.
  statement {
    sid = "CreateOrChangeEnvironmentRolesWithBoundary"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
    ]
    resources = local.environment_roles
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.environment_boundary.arn]
    }
  }

  statement {
    sid       = "AttachOnlyTheEnvironmentManagedPolicies"
    actions   = ["iam:AttachRolePolicy"]
    resources = local.environment_roles
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.environment_boundary.arn]
    }
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.environment_managed_policies
    }
  }

  statement {
    sid = "ManageEnvironmentRolesOnly"
    actions = [
      "iam:DeleteRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = local.environment_roles
  }

  # Roles that AWS creates once per account for EKS, load balancers and VPC links.
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "autoscaling.amazonaws.com",
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "ops.apigateway.amazonaws.com",
      ]
    }
  }

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # Delete is needed for the lock files of the S3 backend.
  statement {
    sid       = "EnvironmentStates"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/envs/*"]
  }

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # The infra pipeline builds the database and RabbitMQ images.
  statement {
    sid       = "PushPlatformImages"
    actions   = local.ecr_push_actions
    resources = [for name in local.platform_images : aws_ecr_repository.this[name].arn]
  }
}

resource "aws_iam_role_policy" "ci_infra" {
  name   = "terraform-environments"
  role   = aws_iam_role.ci["infra"].id
  policy = data.aws_iam_policy_document.ci_infra.json
}

# ---- applications: push their own image, reach the clusters ----------------

locals {
  ecr_push_actions = [
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:CompleteLayerUpload",
    "ecr:DescribeImageScanFindings",
    "ecr:DescribeImages",
    "ecr:GetDownloadUrlForLayer",
    "ecr:InitiateLayerUpload",
    "ecr:PutImage",
    "ecr:UploadLayerPart",
  ]
}

data "aws_iam_policy_document" "ci_application" {
  for_each = toset(var.applications)

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "PushItsOwnImage"
    actions   = local.ecr_push_actions
    resources = [aws_ecr_repository.this[each.key].arn]
  }

  # What the deployment may do inside Kubernetes is set by the EKS access entry
  # of each environment (infra repository): the Kubernetes group
  # code-keeper-deploy-<application>, whose Role covers its own objects only.
  statement {
    sid       = "FindTheClusters"
    actions   = ["eks:DescribeCluster"]
    resources = local.environment_clusters
  }
}

resource "aws_iam_role_policy" "ci_application" {
  for_each = toset(var.applications)

  name   = "push-and-deploy"
  role   = aws_iam_role.ci[each.key].id
  policy = data.aws_iam_policy_document.ci_application[each.key].json
}
