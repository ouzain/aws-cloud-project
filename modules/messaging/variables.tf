variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "notification_email" {
  type        = string
  default     = null
  description = "Destinataire SNS facultatif."
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "worker_sg_id" {
  type = string
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

variable "db_password" {
  type      = string
  sensitive = true
}

variable "application_zip" {
  type = string
}

variable "application_hash" {
  type = string
}
