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
  # CI roles below (no privilege escalation).
  environment_prefixes = [for env in var.environments : "${var.project}-${env}"]
  environment_roles    = [for prefix in local.environment_prefixes : "arn:aws:iam::${local.account_id}:role/${prefix}-*"]
  environment_policies = [for prefix in local.environment_prefixes : "arn:aws:iam::${local.account_id}:policy/${prefix}-*"]
  environment_clusters = [for prefix in local.environment_prefixes : "arn:aws:eks:${var.region}:${local.account_id}:cluster/${prefix}"]

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

# ---- infra: Terraform of the staging and production environments -----------

data "aws_iam_policy_document" "ci_infra" {
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

  statement {
    sid       = "ReadIam"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid = "ManageEnvironmentRolesOnly"
    actions = [
      "iam:AttachRolePolicy",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = local.environment_roles
  }

  statement {
    sid = "ManageEnvironmentPoliciesOnly"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = local.environment_policies
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
  # of each environment (infra repository), limited to the application namespace.
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
