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

output "order_topic_arn" {
  value = module.messaging.topic_arn
}

output "order_queue_url" {
  value = module.messaging.queue_url
}

output "order_consumer_log_group" {
  description = "Log group CloudWatch du consommateur (confirmation -> notification -> traitement)"
  value       = module.messaging.consumer_log_group
}

output "order_notifications_topic_arn" {
  value = module.messaging.notifications_topic_arn
}
