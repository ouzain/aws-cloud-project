variable "project_name" {
  description = "Préfixe utilisé pour nommer et tagger toutes les ressources (ex: vitalora)"
  type        = string
}

variable "owner_tag" {
  description = "Identifie le propriétaire des ressources dans ce compte (ton prénom)"
  type        = string
}

variable "vpc_cidr" {
  description = "Bloc CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Zones de disponibilité utilisées (2 minimum pour la haute dispo exigée par le brief)"
  type        = list(string)
  default     = ["eu-west-3a", "eu-west-3b"]
}

variable "public_subnet_cidrs" {
  description = "Un subnet public par AZ (héberge l'ALB et l'EC2 — pas de NAT Gateway, donc l'EC2 doit être public)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Un subnet privé par AZ (héberge RDS, jamais exposé à Internet)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "admin_cidr" {
  description = "Plage IP autorisée en SSH (22) vers l'EC2. Mets ton IP publique en /32, jamais 0.0.0.0/0."
  type        = string
}
