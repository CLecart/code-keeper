variable "project" {
  description = "Project name, first part of every resource name."
  type        = string
  default     = "code-keeper"
}

variable "environment" {
  description = "Environment name; the resources are named <project>-<environment>-..."
  type        = string

  validation {
    condition     = contains(["staging", "prod"], var.environment)
    error_message = "The environment is staging or prod: the CI role of the infra pipeline only manages these names."
  }
}

variable "region" {
  description = "AWS Region of the environment (Paris)."
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "Range of the environment VPC (a /16): two /19 private and two /24 public subnets are cut from it."
  type        = string
}

variable "eks_api_allowed_cidrs" {
  description = "Public IP ranges allowed to reach the EKS API: the admin machine and the GitLab runner."
  type        = list(string)

  validation {
    condition     = length(var.eks_api_allowed_cidrs) > 0 && !contains(var.eks_api_allowed_cidrs, "0.0.0.0/0")
    error_message = "List at least one range and never 0.0.0.0/0: the cluster API must not be open to the whole Internet."
  }
}

variable "admin_principal_arns" {
  description = "IAM principals given cluster admin rights (kubectl from the admin machine)."
  type        = list(string)
  default     = []
}

variable "applications" {
  description = "Applications deployed by their own pipeline; their CI role joins the Kubernetes group <project>-deploy-<application> (rights: platform/rbac.yaml)."
  type        = list(string)
  default     = ["api-gateway-app", "inventory-app", "billing-app"]
}

variable "kubernetes_version" {
  description = "EKS version. Keep it in standard support (0.10 USD/h); extended support costs 0.50 USD/h."
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Worker node type. The Free plan only accepts the free-tier-eligible types (aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true)."
  type        = string
  default     = "c7i-flex.large"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes (two, one per Availability Zone)."
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Number of worker nodes at creation."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Upper bound for the cluster autoscaler."
  type        = number
  default     = 3
}
