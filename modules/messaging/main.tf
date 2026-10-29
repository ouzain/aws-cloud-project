# ---------------------------------------------------------------------------
# Phase 4 — Événementiel : SNS (fan-out) -> SQS -> Lambda consommatrice
#
#   app (POST /orders) --publish--> SNS vitalora-order-confirmation
#                                     |-- SQS vitalora-order-processing --> Lambda order-processor
#                                     |        (DLQ après 3 échecs)          1. confirmation client
#                                     |                                      2. notification interne
#                                     |                                      3. simulation de traitement
#
#   Lambda --publish (1 message/étape)--> SNS vitalora-order-notifications
#                                           '-- (optionnel) abonnement e-mail
#
# L'ordre confirmation -> notification -> traitement est garanti parce que les
# 3 étapes s'exécutent séquentiellement dans la même invocation Lambda, et que
# chaque notification est publiée (await) avant de passer à l'étape suivante.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  topic_name    = "${var.project_name}-order-confirmation"
  notif_topic   = "${var.project_name}-order-notifications"
  queue_name    = "${var.project_name}-order-processing"
  function_name = "${var.project_name}-order-processor"

  # ARN construit (et non lu sur la ressource) : connu dès le plan, ce qui évite
  # le bug du provider "block count changed from 0 to 1" sur le bloc environment.
  notif_topic_arn = "arn:aws:sns:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.notif_topic}"
}

resource "aws_sns_topic" "order_confirmation" {
  name = local.topic_name

  tags = {
    Name  = local.topic_name
    Owner = var.owner_tag
  }
}

# Second topic : une notification lisible par étape du traitement, publiée par
# la Lambda. L'abonné doit cliquer sur le lien de confirmation reçu par e-mail.
resource "aws_sns_topic" "order_notifications" {
  name = local.notif_topic

  tags = {
    Name  = local.notif_topic
    Owner = var.owner_tag
  }
}

resource "aws_sns_topic_subscription" "email" {
  count = var.notification_email == null ? 0 : 1

  topic_arn = aws_sns_topic.order_notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# --- SQS : file de traitement + DLQ ---------------------------------------

resource "aws_sqs_queue" "order_processing_dlq" {
  name                      = "${local.queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 jours
  sqs_managed_sse_enabled   = true

  tags = {
    Name  = "${local.queue_name}-dlq"
    Owner = var.owner_tag
  }
}

resource "aws_sqs_queue" "order_processing" {
  name = local.queue_name
  # Doit être >= au timeout de la Lambda consommatrice (exigence de l'event source mapping).
  visibility_timeout_seconds = 180
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.order_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name  = local.queue_name
    Owner = var.owner_tag
  }
}

# Seul CE topic peut écrire dans la file.
resource "aws_sqs_queue_policy" "order_processing" {
  queue_url = aws_sqs_queue.order_processing.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowSnsTopicToSend"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.order_processing.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.order_confirmation.arn }
      }
    }]
  })
}

resource "aws_sns_topic_subscription" "order_processing" {
  topic_arn            = aws_sns_topic.order_confirmation.arn
  protocol             = "sqs"
  endpoint             = aws_sqs_queue.order_processing.arn
  raw_message_delivery = true

  depends_on = [aws_sqs_queue_policy.order_processing]
}

# --- Lambda consommatrice --------------------------------------------------

data "archive_file" "consumer" {
  type        = "zip"
  source_file = "${path.module}/lambda/order-processor.js"
  output_path = "${path.module}/.build/order-processor.zip"
}

resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days

  tags = {
    Name  = local.function_name
    Owner = var.owner_tag
  }
}

resource "aws_iam_role" "consumer" {
  name = "${local.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name  = "${local.function_name}-role"
    Owner = var.owner_tag
  }
}

resource "aws_iam_role_policy" "consumer" {
  name = "${local.function_name}-policy"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ConsumeOrderQueue"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.order_processing.arn
      },
      {
        Sid      = "PublishStepNotifications"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.order_notifications.arn
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.consumer.arn}:*"
      }
    ]
  })
}

resource "aws_lambda_function" "consumer" {
  function_name    = local.function_name
  role             = aws_iam_role.consumer.arn
  runtime          = "nodejs20.x"
  handler          = "order-processor.handler"
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      NOTIFICATION_TOPIC_ARN = local.notif_topic_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.consumer, aws_iam_role_policy.consumer, aws_sns_topic.order_notifications]

  tags = {
    Name  = local.function_name
    Owner = var.owner_tag
  }
}

resource "aws_lambda_event_source_mapping" "consumer" {
  event_source_arn = aws_sqs_queue.order_processing.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 5

  # Un message en échec est re-livré seul (puis DLQ), sans rejouer tout le lot.
  function_response_types = ["ReportBatchItemFailures"]
}
