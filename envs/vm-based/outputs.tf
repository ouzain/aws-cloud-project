output "alb_dns_name" {
  description = "URL de test : http://<cette_valeur>/"
  value       = module.compute_vm.alb_dns_name
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "assets_bucket_name" {
  value = module.database.assets_bucket_name
}
