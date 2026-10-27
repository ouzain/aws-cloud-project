# Copie en "backend-ouzain.hcl" (gitignored) après avoir créé ton bucket S3
# de state (une fois, manuellement — voir README).

bucket = "tfstate-vitalora-ouzain"
key    = "vm-based/terraform.tfstate"
region = "eu-west-3"
profile = "default"
encrypt = true
