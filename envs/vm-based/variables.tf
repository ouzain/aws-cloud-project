variable "aws_region" {
  type        = string
  default     = "eu-west-3"
  description = "Région AWS du déploiement."
}

variable "aws_profile" {
  type        = string
  default     = ""
  description = "Laisser vide avec les identifiants temporaires du script."
}

variable "project_name" {
  type        = string
  default     = "vitalora"
  description = "Préfixe des ressources du projet."
}

variable "owner_tag" {
  type        = string
  default     = "team"
  description = "Étiquette du propriétaire des ressources."
}

variable "admin_cidr" {
  type        = string
  default     = null
  description = "CIDR administrateur SSH facultatif."
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Type d’instance EC2 de démonstration."
}

variable "desired_capacity" {
  type        = number
  default     = 1
  description = "Utiliser deux instances pour la démonstration de haute disponibilité."
  validation {
    condition     = contains([1, 2], var.desired_capacity)
    error_message = "La démonstration accepte une ou deux instances."
  }
}

variable "key_name" {
  type        = string
  default     = null
  description = "Paire de clés EC2 existante facultative."
}

variable "notification_email" {
  type        = string
  default     = null
  description = "Adresse e-mail SNS confirmée facultative."
}

variable "existing_audit_trail_name" {
  type        = string
  default     = null
  description = "Journal d’audit existant détecté par le script d’initialisation."
}
variable "existing_budget_name" {
  type        = string
  default     = null
  description = "Budget existant détecté par le script d’initialisation."
}
variable "budget_alert_email" {
  type        = string
  default     = null
  sensitive   = true
  description = "Requis si le compte ne possède aucun budget VITALORA."
}
