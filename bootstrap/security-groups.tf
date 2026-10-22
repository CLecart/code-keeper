resource "aws_security_group" "gitlab" {
  name        = "${var.project}-gitlab"
  description = "GitLab: web and SSH from the admin, web from the runner"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.project}-gitlab" }
}

resource "aws_security_group" "runner" {
  name        = "${var.project}-runner"
  description = "GitLab Runner: SSH from the admin only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.project}-runner" }
}

locals {
  gitlab_admin_ports = {
    ssh   = 22
    http  = 80
    https = 443
  }
  admin_rules = {
    for pair in setproduct(keys(local.gitlab_admin_ports), var.admin_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = local.gitlab_admin_ports[pair[0]], cidr = pair[1] }
  }
  team_rules = {
    for pair in setproduct(["http", "https"], var.team_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = local.gitlab_admin_ports[pair[0]], cidr = pair[1] }
  }
}

resource "aws_vpc_security_group_ingress_rule" "gitlab_admin" {
  for_each = local.admin_rules

  security_group_id = aws_security_group.gitlab.id
  description       = "Admin ${each.key}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# The other team members (developer, stakeholder...) only need the web interface
# and Git over HTTPS: no SSH to the machines.
resource "aws_vpc_security_group_ingress_rule" "gitlab_team" {
  for_each = local.team_rules

  security_group_id = aws_security_group.gitlab.id
  description       = "Team ${each.key}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
}

# The runner reaches GitLab through its public URL, so the traffic leaves the VPC
# and comes back from the runner's Elastic IP: a rule on the runner's security
# group would not match it.
resource "aws_vpc_security_group_ingress_rule" "gitlab_from_runner" {
  security_group_id = aws_security_group.gitlab.id
  description       = "Runner HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "${aws_eip.runner.public_ip}/32"
}

resource "aws_vpc_security_group_ingress_rule" "runner_admin_ssh" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.runner.id
  description       = "Admin ssh"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# Both machines download packages, images and providers from the Internet.
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = {
    gitlab = aws_security_group.gitlab.id
    runner = aws_security_group.runner.id
  }

  security_group_id = each.value
  description       = "Outbound to the Internet"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
