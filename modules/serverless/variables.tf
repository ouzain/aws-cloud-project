variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type        = string
  description = "Nom du projet"
}

variable "owner_tag" {
  type        = string
  description = "Propriétaire des ressources pour le suivi budgétaire"
}


variable "notification_email" {
  type        = string
  description = "Email pour recevoir la confirmation de commande SNS"
  default     = "amaniesaid@gmail.com" 
}