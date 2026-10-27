# Backend volontairement vide : chaque personne fournit sa propre config au
# `terraform init` via -backend-config (voir backend-example.hcl + README).
# Ça garantit un state strictement personnel, jamais partagé entre comptes
# (voir la section "Organisation d'équipe" du roadmap).

terraform {
  backend "s3" {}
}
