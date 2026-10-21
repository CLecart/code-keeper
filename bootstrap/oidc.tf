# OpenID Connect between GitLab CI and AWS: a job receives a short-lived ID
# token signed by GitLab (id_tokens keyword) and exchanges it with AWS STS for
# the role of its own project, only on the protected main branch. No AWS key is
# stored anywhere.
#
# GitLab itself stays closed to the Internet, so STS cannot read its public
# signing keys there. As the GitLab documentation describes for a non-public
# instance, its OpenID configuration and public keys are copied (by Ansible) to
# this bucket, the only thing AWS reads, and GitLab signs the tokens with this
# bucket as issuer (gitlab_rails['ci_id_tokens_issuer_url']).

data "aws_caller_identity" "current" {}

locals {
  account_id    = data.aws_caller_identity.current.account_id
  oidc_host     = aws_s3_bucket.oidc.bucket_regional_domain_name
  oidc_issuer   = "https://${local.oidc_host}"
  oidc_audience = "sts.amazonaws.com"

  # Public objects of the bucket: the two documents STS reads.
  oidc_documents = [".well-known/openid-configuration", "oauth/discovery/keys"]
}

resource "aws_s3_bucket" "oidc" {
  bucket_prefix = "${var.project}-oidc-"
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ACLs stay blocked; only the bucket policy below may make the two documents public.
resource "aws_s3_bucket_public_access_block" "oidc" {
  bucket = aws_s3_bucket.oidc.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = false
}

# Anyone may read the two public documents over HTTPS, nothing else. Writing
# needs the administrator's IAM permissions (Ansible from the admin machine):
# no CI role can change the keys AWS trusts.
data "aws_iam_policy_document" "oidc_bucket" {
  statement {
    sid       = "PublicReadOfTheDiscoveryDocuments"
    actions   = ["s3:GetObject"]
    resources = [for doc in local.oidc_documents : "${aws_s3_bucket.oidc.arn}/${doc}"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.oidc.arn,
      "${aws_s3_bucket.oidc.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "oidc" {
  bucket = aws_s3_bucket.oidc.id
  policy = data.aws_iam_policy_document.oidc_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.oidc]
}

data "tls_certificate" "oidc" {
  url = local.oidc_issuer
}

# Without a thumbprint, IAM reads the OpenID configuration at creation time and
# refuses the provider while the bucket is still empty (Ansible uploads the
# documents once GitLab uses this issuer). With one, the creation succeeds; AWS
# then checks the S3 certificate against its trusted CAs anyway, so a later
# certificate rotation needs no update.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = local.oidc_issuer
  client_id_list  = [local.oidc_audience]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  lifecycle {
    ignore_changes = [thumbprint_list]
  }
}
