terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # Pin to a modern provider that supports the LT fields used by the module
      version = ">= 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}
