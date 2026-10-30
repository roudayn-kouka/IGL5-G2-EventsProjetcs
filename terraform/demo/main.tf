
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "aws_region" {
  type = string
}

variable "demo_name" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "demo" {
  name        = var.demo_name
  description = "Temporary Jenkins Terraform demonstration"
  vpc_id      = data.aws_vpc.default.id

  ingress = []
  egress  = []

  tags = {
    Project   = "FST-Events"
    ManagedBy = "Terraform"
  }
}

output "security_group_id" {
  value = aws_security_group.demo.id
}
