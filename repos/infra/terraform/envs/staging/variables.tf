# Both values come from the CI variables TF_VAR_eks_api_allowed_cidrs and
# TF_VAR_admin_principal_arns, set by Ansible from the bootstrap outputs.

variable "eks_api_allowed_cidrs" {
  description = "Public IP ranges allowed to reach the EKS API: the admin machine and the GitLab runner."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "IAM principals given cluster admin rights (kubectl from the admin machine)."
  type        = list(string)
  default     = []
}
