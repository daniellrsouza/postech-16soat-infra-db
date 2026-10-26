terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # bucket vem de `terraform init -backend-config=bucket=...` (scripts/tf.sh).
  backend "s3" {
    key          = "infra-db/shared.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project    = "postech-16soat"
      Repository = "postech-16soat-infra-db"
      Stack      = "shared"
      ManagedBy  = "terraform"
    }
  }
}
