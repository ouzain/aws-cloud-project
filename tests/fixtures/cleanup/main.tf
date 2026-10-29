# Banc isolé : mêmes adresses que le projet, sans réseau ni base de données.
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 5.100.0" }
  }
}

variable "aws_region" { type = string }
variable "aws_profile" { type = string }
variable "project_name" { type = string }

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
  default_tags {
    tags = { Project = var.project_name, Env = "cleanup-test" }
  }
}

module "messaging" {
  source       = "./messaging"
  project_name = var.project_name
}
