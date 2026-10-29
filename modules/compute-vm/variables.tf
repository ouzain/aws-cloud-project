variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "ec2_sg_id" {
  type = string
}

variable "alb_sg_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "desired_capacity" {
  type = number
}

variable "db_endpoint" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password_ssm_name" {
  type = string
}

variable "assets_bucket_name" {
  type = string
}

variable "application_key" {
  type = string
}

variable "order_topic_arn" {
  type = string
}
