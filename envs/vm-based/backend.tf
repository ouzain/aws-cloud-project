# Le script scripts/terraform.py initialise le stockage S3 chiffré de l’état.
terraform {
  backend "s3" {}
}
