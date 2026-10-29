variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "notification_email" {
  description = "Adresse e-mail abonnée au topic de notifications (1 e-mail par étape : confirmation, notification interne, traitement). null = pas d'abonnement ; les traces CloudWatch Logs restent émises dans tous les cas."
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}
