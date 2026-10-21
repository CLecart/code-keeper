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

output "runner_role_arn" {
  description = "IAM role the CI jobs run with."
  value       = aws_iam_role.runner.arn
}
