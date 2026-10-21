variable "region" {
  description = "AWS Region of the whole project (Paris)."
  type        = string
  default     = "eu-west-3"
}

variable "project" {
  description = "Name prefix of every resource."
  type        = string
  default     = "code-keeper"
}

variable "admin_cidrs" {
  description = "Public IP ranges allowed to reach GitLab (web, SSH) and the runner (SSH), e.g. [\"203.0.113.7/32\"]."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "List at least one range and never 0.0.0.0/0: GitLab must not be open to the whole Internet."
  }
}

variable "ssh_public_key_path" {
  description = "Public key installed on both machines; Ansible connects with the matching private key."
  type        = string
  default     = "~/.ssh/code-keeper.pub"
}

variable "vpc_cidr" {
  description = "Range of the tooling VPC (GitLab and runner). Kept apart from the staging and production VPCs."
  type        = string
  default     = "10.100.0.0/24"
}

variable "gitlab_instance_type" {
  description = "GitLab machine. GitLab needs 8 GB of memory at least; m7i-flex.large (8 GiB) is the largest free-plan-eligible type."
  type        = string
  default     = "m7i-flex.large"
}

variable "runner_instance_type" {
  description = "Runner machine, separate from GitLab as the GitLab Runner documentation advises."
  type        = string
  default     = "c7i-flex.large"
}

variable "gitlab_volume_size" {
  description = "System disk of the GitLab machine in GB (GitLab asks for 40 GB)."
  type        = number
  default     = 40
}

variable "runner_volume_size" {
  description = "System disk of the runner machine in GB (Docker images and build cache)."
  type        = number
  default     = 30
}

variable "images" {
  description = "One ECR repository per image, shared by staging and production."
  type        = list(string)
  default = [
    "api-gateway",
    "inventory-app",
    "inventory-database",
    "billing-app",
    "billing-database",
    "rabbitmq-server",
  ]
}

variable "images_to_keep" {
  description = "Number of images kept per repository; older ones are expired by the lifecycle policy."
  type        = number
  default     = 5
}
