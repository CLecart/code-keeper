terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.69"
    }
  }

  # State in the S3 bucket created by bootstrap/ (code-keeper repository). The
  # bucket name is not in the code: the pipeline passes it from the CI variable
  # TF_STATE_BUCKET (terraform init -backend-config="bucket=$TF_STATE_BUCKET").
  backend "s3" {
    key          = "envs/prod/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = "code-keeper"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# Same module and same settings as the other environment: only the name and
# the VPC range differ.
module "environment" {
  source = "../../modules/environment"

  environment           = "prod"
  vpc_cidr              = "10.1.0.0/16"
  eks_api_allowed_cidrs = var.eks_api_allowed_cidrs
  admin_principal_arns  = var.admin_principal_arns
}
