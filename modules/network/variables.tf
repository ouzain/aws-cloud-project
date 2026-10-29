variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "admin_cidr" {
  type        = string
  default     = null
  description = "CIDR IPv4 administrateur facultatif. Null désactive SSH."
}
