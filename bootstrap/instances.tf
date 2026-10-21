# Ubuntu 24.04 LTS, supported by GitLab and GitLab Runner. The parameter always
# points to the latest image; ignore_changes below keeps a new image from
# replacing a machine (and wiping GitLab) at the next apply.
data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.project}-admin"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "aws_instance" "gitlab" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.gitlab_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.gitlab.id]
  # Public on purpose: the admin and the runner reach it through its Elastic IP,
  # and the gitlab security group only lets in the admin IP and the runner.
  associate_public_ip_address = true
  key_name                    = aws_key_pair.admin.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.gitlab_volume_size
    encrypted   = true
  }

  # IMDSv2 only; GitLab itself needs no AWS permission.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.project}-gitlab" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_instance" "runner" {
  ami                    = data.aws_ssm_parameter.ubuntu.value
  instance_type          = var.runner_instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.runner.id]
  # Public on purpose: the admin and the runner reach it through its Elastic IP,
  # and the runner security group only lets in the admin IP.
  associate_public_ip_address = true
  key_name                    = aws_key_pair.admin.key_name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.runner_volume_size
    encrypted   = true
  }

  # No instance role: each job gets the role of its own project through OIDC
  # (oidc.tf, iam.tf). Hop limit 1 keeps the job containers away from the
  # instance metadata service altogether.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = { Name = "${var.project}-runner" }

  lifecycle {
    ignore_changes = [ami]
  }
}

# Fixed public addresses: the GitLab URL, its certificate and the firewall rules
# keep working after each stop/start. 0.005 USD/h each, running or not.
resource "aws_eip" "gitlab" {
  domain   = "vpc"
  instance = aws_instance.gitlab.id

  tags = { Name = "${var.project}-gitlab" }
}

resource "aws_eip" "runner" {
  domain   = "vpc"
  instance = aws_instance.runner.id

  tags = { Name = "${var.project}-runner" }
}
