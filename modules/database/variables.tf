variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "application_zip" {
  type = string
}

variable "application_hash" {
  type = string
}
