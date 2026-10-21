# One environment of the code-keeper project: the cloud-design architecture
# (VPC, EKS, internal ALB, API Gateway with Cognito, CloudWatch). Staging and
# production call this module with the same settings; only their name and
# their VPC range differ.

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Cluster name and prefix of every resource. The CI role of the infra
  # pipeline may only manage IAM roles and policies starting with it.
  name = "${var.project}-${var.environment}"

  account_id = data.aws_caller_identity.current.account_id
  azs        = slice(data.aws_availability_zones.available.names, 0, 2)
}
