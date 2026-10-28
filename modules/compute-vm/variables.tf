variable "project_name" {
  type = string
}

variable "owner_tag" {
  type = string
}

variable "aws_region" {
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
  description = "t3.micro / t2.micro = éligible Free Tier legacy (750h/mois)"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Nom d'une key pair EC2 existante pour le SSH (optionnel — laisse null si tu n'en as pas besoin)"
  type        = string
  default     = null
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 2
}

variable "desired_capacity" {
  type    = number
  default = 1
}

# --- Connexion à la base (sortie du module "database") ---------------------

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
  description = "Nom du paramètre SSM SecureString — l'EC2 va le lire au boot via son rôle IAM"
  type        = string
}

variable "assets_bucket_name" {
  type = string
}

variable "order_topic_arn" {
  description = "ARN du topic SNS order-confirmation sur lequel l'app publie à chaque commande"
  type        = string
}
