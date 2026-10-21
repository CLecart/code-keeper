# Role of the runner machine: the CI jobs get short-lived credentials from it,
# so no AWS key is stored in GitLab. This first version only allows what the CI
# needs (push images, use the Terraform state bucket); the deployment
# permissions are added with the infrastructure pipeline.
data "aws_iam_policy_document" "runner_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = "${var.project}-runner"
  assume_role_policy = data.aws_iam_policy_document.runner_assume.json
}

resource "aws_iam_instance_profile" "runner" {
  name = "${var.project}-runner"
  role = aws_iam_role.runner.name
}

data "aws_iam_policy_document" "runner" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushPullProjectImages"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeImageScanFindings",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [for repo in aws_ecr_repository.this : repo.arn]
  }

  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # Delete is needed for the lock files of the S3 backend.
  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "ci-images-and-state"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner.json
}
