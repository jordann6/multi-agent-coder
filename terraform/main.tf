terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "tf-backend-jord-projs"
    key            = "multi-agent-coder/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-backend-jord-projs-lock"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
