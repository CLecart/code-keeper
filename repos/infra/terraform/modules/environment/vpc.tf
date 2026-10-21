# Two Availability Zones, each with a public subnet (load balancers, NAT) and a
# private subnet (worker nodes, pods, databases). The private subnets are large
# because the VPC CNI gives every pod an address from them.
#   /16 -> private 0.0/19 and 32.0/19, public 96.0/24 and 97.0/24
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [cidrsubnet(var.vpc_cidr, 3, 0), cidrsubnet(var.vpc_cidr, 3, 1)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 96), cidrsubnet(var.vpc_cidr, 8, 97)]

  # One NAT gateway (0.05 USD/h) instead of one per zone: the nodes keep pulling
  # images if a zone fails only while the NAT zone is up, an accepted trade-off.
  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true

  # Subnet discovery for load balancers created from Kubernetes.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
