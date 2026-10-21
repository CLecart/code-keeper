output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Command that adds the cluster to ~/.kube/config."
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "api_url" {
  description = "Public HTTPS URL of the application (API Gateway)."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "cognito_user_pool_id" {
  description = "Cognito user pool of the API users."
  value       = aws_cognito_user_pool.this.id
}

output "cognito_client_id" {
  description = "App client the users sign in with; also the audience checked by API Gateway."
  value       = aws_cognito_user_pool_client.api.id
}

output "container_log_group" {
  description = "CloudWatch log group of the services (Fluent Bit)."
  value       = aws_cloudwatch_log_group.containers.name
}

output "dashboard_url" {
  description = "CloudWatch dashboard of API Gateway and of the internal load balancer."
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.platform.dashboard_name}"
}

output "alb_target_group_arn" {
  description = "Target group of the worker nodes (aws elbv2 describe-target-health)."
  value       = aws_lb_target_group.api_gateway.arn
}

output "vpc_id" {
  description = "VPC of the environment."
  value       = module.vpc.vpc_id
}
