output "gitlab_public_ip" {
  description = "Elastic IP of GitLab (web and SSH)."
  value       = aws_eip.gitlab.public_ip
}

output "runner_public_ip" {
  description = "Elastic IP of the runner; the environments allow it on their Kubernetes API."
  value       = aws_eip.runner.public_ip
}

output "instance_ids" {
  description = "Machines to stop at the end of each session and start at the next one."
  value = {
    gitlab = aws_instance.gitlab.id
    runner = aws_instance.runner.id
  }
}

output "ssh_commands" {
  description = "SSH access with the admin key (user ubuntu)."
  value = {
    gitlab = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${aws_eip.gitlab.public_ip}"
    runner = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ubuntu@${aws_eip.runner.public_ip}"
  }
}

output "registry" {
  description = "ECR registry host, used by `docker login` and in the image names."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "repository_urls" {
  description = "Image name => repository URL."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "state_bucket" {
  description = "S3 bucket of the staging and production Terraform states."
  value       = aws_s3_bucket.state.bucket
}

output "eks_api_allowed_cidrs" {
  description = "Ranges allowed on the EKS API of the environments: the admin IP and the runner (CI variable TF_VAR_eks_api_allowed_cidrs)."
  value       = concat(var.admin_cidrs, ["${aws_eip.runner.public_ip}/32"])
}

output "admin_principal_arn" {
  description = "IAM identity running this stack, made cluster admin of the environments (CI variable TF_VAR_admin_principal_arns)."
  value       = data.aws_caller_identity.current.arn
}

output "oidc_issuer_url" {
  description = "Issuer of the GitLab CI ID tokens (gitlab_rails['ci_id_tokens_issuer_url'])."
  value       = local.oidc_issuer
}

output "oidc_bucket" {
  description = "Bucket holding the public OpenID configuration and keys of GitLab."
  value       = aws_s3_bucket.oidc.bucket
}

output "ci_role_arns" {
  description = "GitLab project => IAM role its main branch assumes (CI variable AWS_ROLE_ARN)."
  value       = { for name, role in aws_iam_role.ci : name => role.arn }
}
