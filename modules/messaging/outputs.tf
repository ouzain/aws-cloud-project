output "topic_arn" {
  value = aws_sns_topic.order_confirmation.arn
}

output "queue_url" {
  value = aws_sqs_queue.order_processing.id
}

output "dlq_url" {
  value = aws_sqs_queue.order_processing_dlq.id
}

output "consumer_log_group" {
  value = aws_cloudwatch_log_group.consumer.name
}

output "function_name" {
  value = aws_lambda_function.consumer.function_name
}
