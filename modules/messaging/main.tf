resource "aws_sns_topic" "order_confirmation" { name = "${var.project_name}-order-confirmation" }
resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == null ? 0 : 1
  topic_arn = aws_sns_topic.order_confirmation.arn
  protocol  = "email"
  endpoint  = var.notification_email
}
resource "aws_sqs_queue" "order_processing_dlq" {
  name                      = "${var.project_name}-order-processing-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
}
resource "aws_sqs_queue" "order_processing" {
  name                       = "${var.project_name}-order-processing"
  visibility_timeout_seconds = 180
  sqs_managed_sse_enabled    = true
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_processing_dlq.arn
    maxReceiveCount     = 3
  })
}
resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url            = aws_sqs_queue.order_processing_dlq.id
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.order_processing.arn] })
}
resource "aws_sqs_queue_policy" "order_processing" {
  queue_url = aws_sqs_queue.order_processing.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.order_processing.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_confirmation.arn } }
    }]
  })
}
resource "aws_sns_topic_subscription" "order_processing" {
  topic_arn            = aws_sns_topic.order_confirmation.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.order_processing.arn
  raw_message_delivery = true
  depends_on           = [aws_sqs_queue_policy.order_processing]
}
resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${var.project_name}-order-processor"
  retention_in_days = 7
}
resource "aws_iam_role" "consumer" {
  name = "${var.project_name}-order-processor-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy" "consumer" {
  name = "${var.project_name}-order-processor-policy"
  role = aws_iam_role.consumer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.order_processing.arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.consumer.arn}:*" },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets", "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"]
        Resource = "*"
      }
    ]
  })
}
resource "aws_lambda_function" "consumer" {
  function_name    = "${var.project_name}-order-processor"
  role             = aws_iam_role.consumer.arn
  runtime          = "nodejs22.x"
  handler          = "modules/messaging/lambda/order-processor.handler"
  filename         = var.application_zip
  source_code_hash = var.application_hash
  timeout          = 30
  memory_size      = 256
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.worker_sg_id]
  }
  environment {
    variables = {
      DB_HOST     = var.db_endpoint
      DB_PORT     = "3306"
      DB_NAME     = var.db_name
      DB_USER     = var.db_username
      DB_PASSWORD = var.db_password
      DB_TLS      = "true"
    }
  }
  depends_on = [aws_cloudwatch_log_group.consumer, aws_iam_role_policy.consumer]
}
resource "aws_lambda_event_source_mapping" "consumer" {
  event_source_arn        = aws_sqs_queue.order_processing.arn
  function_name           = aws_lambda_function.consumer.arn
  batch_size              = 5
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config { maximum_concurrency = 2 }
}
