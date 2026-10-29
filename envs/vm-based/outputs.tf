output "alb_dns_name" {
  value = module.compute_vm.alb_dns_name
}

output "asg_name" {
  value = module.compute_vm.asg_name
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

output "order_dlq_url" {
  value = module.messaging.dlq_url
}

output "order_consumer_log_group" {
  value = module.messaging.consumer_log_group
}

output "order_worker_function" {
  value = module.messaging.function_name
}

output "application_log_group" {
  value = module.compute_vm.application_log_group
}

output "dashboard_name" { value = module.monitoring.dashboard_name }
output "alarm_names" { value = module.monitoring.alarm_names }
output "audit_trail_arn" { value = module.monitoring.audit_trail_arn }
output "budget_name" { value = module.monitoring.budget_name }
