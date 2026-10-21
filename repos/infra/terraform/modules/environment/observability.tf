# Observability on the AWS side:
#   - CloudWatch log group of the services, filled by Fluent Bit
#     (platform/helm/fluent-bit.yaml) through EKS Pod Identity;
#   - a CloudWatch dashboard of the public entry (API Gateway) and of the
#     internal load balancer.
# Metrics and dashboards of the cluster itself come from Prometheus and Grafana
# (platform/helm/kube-prometheus-stack.yaml).
#
# Cost: log ingestion and storage stay within the 5 GB/month free tier (only the
# application containers are shipped, kept one day); AWS service metrics are free
# and the first three dashboards too.

locals {
  container_log_group = "/aws/eks/${local.name}/containers"
}

resource "aws_cloudwatch_log_group" "containers" {
  name              = local.container_log_group
  retention_in_days = 1
}

resource "aws_iam_role" "fluent_bit" {
  name = "${local.name}-fluent-bit"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# The log group is created by Terraform (auto_create_group false in Fluent Bit),
# so writing streams and events into this group only is enough.
resource "aws_iam_role_policy" "fluent_bit" {
  name = "write-container-logs"
  role = aws_iam_role.fluent_bit.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.containers.arn}:*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "fluent_bit" {
  cluster_name    = module.eks.cluster_name
  namespace       = "logging"
  service_account = "fluent-bit"
  role_arn        = aws_iam_role.fluent_bit.arn
}

resource "aws_cloudwatch_dashboard" "platform" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "API Gateway: requests and errors"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 60
          metrics = [for m in ["Count", "4xx", "5xx"] : ["AWS/ApiGateway", m, "ApiId", aws_apigatewayv2_api.this.id]]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title   = "API Gateway: latency (ms)"
          region  = var.region
          view    = "timeSeries"
          period  = 60
          metrics = [["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.this.id, { stat = "p90" }]]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Internal ALB: healthy and unhealthy nodes"
          region = var.region
          view   = "timeSeries"
          stat   = "Minimum"
          period = 60
          metrics = [for m in ["HealthyHostCount", "UnHealthyHostCount"] :
            ["AWS/ApplicationELB", m, "TargetGroup", aws_lb_target_group.api_gateway.arn_suffix, "LoadBalancer", aws_lb.api.arn_suffix]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Internal ALB: target response time (s) and 5xx"
          region = var.region
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.api.arn_suffix, { stat = "p90" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.api.arn_suffix, { stat = "Sum", yAxis = "right" }],
          ]
        }
      },
    ]
  })
}
