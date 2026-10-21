# Internal Application Load Balancer in front of the api-gateway pods.
#
# It lives in the private subnets, without any public address: the only public
# entry is API Gateway, which reaches it through a VPC link. Terraform owns it,
# so `terraform destroy` deletes it as well (a load balancer created from
# Kubernetes would outlive the cluster and keep being billed).
#
#   ALB :80  ->  every worker node :30080 (NodePort of the api-gateway Service)
#            ->  kube-proxy  ->  one of the api-gateway pods :3000

locals {
  # Must match spec.ports[].nodePort of the api-gateway Service (api-gateway-app repository).
  api_gateway_node_port = 30080
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Internal ALB of the api-gateway: HTTP from inside the VPC only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP from the API Gateway VPC link only"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.vpc_link.id
}

# Terraform removes the default allow-all egress rule of a new security group:
# the ALB may only reach the api-gateway NodePort (traffic and health checks).
resource "aws_vpc_security_group_egress_rule" "alb_to_nodes" {
  security_group_id            = aws_security_group.alb.id
  description                  = "api-gateway NodePort on the worker nodes"
  ip_protocol                  = "tcp"
  from_port                    = local.api_gateway_node_port
  to_port                      = local.api_gateway_node_port
  referenced_security_group_id = module.eks.node_security_group_id
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = module.eks.node_security_group_id
  description                  = "api-gateway NodePort from the internal ALB"
  ip_protocol                  = "tcp"
  from_port                    = local.api_gateway_node_port
  to_port                      = local.api_gateway_node_port
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_lb" "api" {
  name               = "${local.name}-api"
  internal           = true
  load_balancer_type = "application"
  subnets            = module.vpc.private_subnets
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "api_gateway" {
  name                 = "${local.name}-api-gateway"
  port                 = local.api_gateway_node_port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = module.vpc.vpc_id
  deregistration_delay = 30

  health_check {
    path = "/health"
    # /health answers 503 while RabbitMQ is down, and an ALB matcher only accepts
    # 200-499. Every node then turns unhealthy, and an ALB whose targets are all
    # unhealthy routes to all of them anyway (fail open): /api/movies keeps working.
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api_gateway.arn
  }
}

# Registers every worker node of the managed node group in the target group,
# including the nodes added later by the cluster autoscaler.
resource "aws_autoscaling_attachment" "api_gateway" {
  autoscaling_group_name = module.eks.eks_managed_node_groups_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.api_gateway.arn
}
