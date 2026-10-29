output "topic_arn" {
  description = "ARN du topic SNS order-confirmation (publié par l'app à chaque commande)"
  value       = aws_sns_topic.order_confirmation.arn
}

output "queue_url" {
  value = aws_sqs_queue.order_processing.id
}

output "dlq_url" {
  value = aws_sqs_queue.order_processing_dlq.id
}

output "consumer_log_group" {
  description = "Log group CloudWatch où lire confirmation -> notification interne -> traitement"
  value       = aws_cloudwatch_log_group.consumer.name
}

output "notifications_topic_arn" {
  description = "Topic SNS des notifications par étape (e-mail)"
  value       = aws_sns_topic.order_notifications.arn
}
