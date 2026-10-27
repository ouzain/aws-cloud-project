variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets privés (2 AZ minimum) pour le DB subnet group"
  type        = list(string)
}

variable "rds_sg_id" {
  type = string
}

variable "db_name" {
  type    = string
  default = "vitalora"
}

variable "db_username" {
  type    = string
  default = "vitalora_admin"
}

variable "instance_class" {
  description = "db.t3.micro / db.t4g.micro = éligible Free Tier legacy, sinon payé via crédits (voir Gouvernance budgétaire)"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "engine_version" {
  description = "Version majeure MySQL — laisser Terraform suivre les mises à jour mineures"
  type        = string
  default     = "8.0"
}
