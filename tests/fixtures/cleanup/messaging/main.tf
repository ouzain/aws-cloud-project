variable "project_name" { type = string }

resource "aws_sqs_queue" "order_processing" {
  name                       = "${var.project_name}-order-processing"
  visibility_timeout_seconds = 30
  sqs_managed_sse_enabled    = true
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
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.consumer.arn}:*" }
    ]
  })
}

resource "aws_lambda_function" "consumer" {
  function_name    = "${var.project_name}-order-processor"
  role             = aws_iam_role.consumer.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  filename         = "${path.root}/worker.zip"
  source_code_hash = filebase64sha256("${path.root}/worker.zip")
  timeout          = 3
  memory_size      = 128
  depends_on       = [aws_cloudwatch_log_group.consumer, aws_iam_role_policy.consumer]
}

resource "aws_lambda_event_source_mapping" "consumer" {
  event_source_arn = aws_sqs_queue.order_processing.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}
