variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "aws_profile" {
  description = "Profil AWS CLI local (aws configure --profile <toi>)"
  type        = string
}

variable "project_name" {
  type    = string
  default = "vitalora"
}

variable "owner_tag" {
  description = "Ton prénom — tague toutes les ressources pour les retrouver dans ta console"
  type        = string
}

variable "admin_cidr" {
  description = "Ton IP publique en /32 (ex: 90.12.34.56/32), pour le SSH vers l'EC2"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  type    = string
  default = null
}
