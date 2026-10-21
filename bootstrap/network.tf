# Small VPC for the tooling machines: one public subnet, no NAT gateway
# (0.05 USD/h). Each machine gets its own Elastic IP instead.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-tooling" }
}

# The default security group of the VPC allows all traffic between its members:
# strip every rule so only the explicit groups below are used.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.project}-tooling" }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.vpc_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  # Public addresses come from the Elastic IPs, which stay the same across a stop/start.
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-tooling-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.project}-tooling-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
