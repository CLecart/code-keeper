output "cluster_name" {
  description = "EKS cluster name."
  value       = module.environment.cluster_name
}

output "configure_kubectl" {
  description = "Command that adds the cluster to ~/.kube/config."
  value       = module.environment.configure_kubectl
}

output "api_url" {
  description = "Public HTTPS URL of the application (API Gateway)."
  value       = module.environment.api_url
}

output "cognito_user_pool_id" {
  description = "Cognito user pool of the API users."
  value       = module.environment.cognito_user_pool_id
}

output "cognito_client_id" {
  description = "App client the users sign in with."
  value       = module.environment.cognito_client_id
}

output "container_log_group" {
  description = "CloudWatch log group of the services (Fluent Bit)."
  value       = module.environment.container_log_group
}

output "dashboard_url" {
  description = "CloudWatch dashboard of API Gateway and of the internal load balancer."
  value       = module.environment.dashboard_url
}

output "alb_target_group_arn" {
  description = "Target group of the worker nodes."
  value       = module.environment.alb_target_group_arn
}
