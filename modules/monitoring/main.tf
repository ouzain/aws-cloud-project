data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  create_trail = var.existing_audit_trail_name == null
  trail_name   = "${var.project_name}-management"
  trail_arn    = local.create_trail ? "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${local.trail_name}" : "arn:aws:cloudtrail:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:trail/${var.existing_audit_trail_name}"
  alarms = {
    cpu                 = { namespace = "AWS/EC2", metric = "CPUUtilization", statistic = "Average", period = 300, threshold = 80, dimensions = { AutoScalingGroupName = var.asg_name } }
    lambda_errors       = { namespace = "AWS/Lambda", metric = "Errors", statistic = "Sum", period = 60, threshold = 1, dimensions = { FunctionName = var.function_name } }
    processing_failures = { namespace = "VITALORA/Orders", metric = "ProcessingFailures", statistic = "Sum", period = 60, threshold = 1, dimensions = {} }
    dlq                 = { namespace = "AWS/SQS", metric = "ApproximateNumberOfMessagesVisible", statistic = "Maximum", period = 60, threshold = 1, dimensions = { QueueName = "${var.project_name}-order-processing-dlq" } }
  }
}

resource "aws_s3_bucket" "audit" {
  count         = local.create_trail ? 1 : 0
  bucket        = "${var.project_name}-audit-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "audit" {
  count                   = local.create_trail ? 1 : 0
  bucket                  = aws_s3_bucket.audit[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "audit" {
  count  = local.create_trail ? 1 : 0
  bucket = aws_s3_bucket.audit[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "audit" {
  count  = local.create_trail ? 1 : 0
  bucket = aws_s3_bucket.audit[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.audit[0].arn
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn, "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
      },
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "aws:SourceArn" = local.trail_arn, "aws:SourceAccount" = data.aws_caller_identity.current.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}
resource "aws_cloudtrail" "management" {
  count                         = local.create_trail ? 1 : 0
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.audit[0].id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
  depends_on = [aws_s3_bucket_policy.audit]
}

resource "aws_budgets_budget" "monthly" {
  count        = var.existing_budget_name == null ? 1 : 0
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = "40"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  dynamic "notification" {
    for_each = toset([20, 50, 80])
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }
  lifecycle {
    precondition {
      condition     = var.budget_alert_email != null
      error_message = "Renseigner budget_alert_email si le compte ne possède aucun budget du projet."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "processing_failures" {
  name           = "${var.project_name}-processing-failures"
  log_group_name = var.worker_log_group
  pattern        = "{ $.event = \"order_pipeline_error\" }"
  metric_transformation {
    name          = "ProcessingFailures"
    namespace     = "VITALORA/Orders"
    value         = "1"
    default_value = 0
    unit          = "Count"
  }
}
resource "aws_cloudwatch_metric_alarm" "health" {
  for_each            = local.alarms
  alarm_name          = "${var.project_name}-${each.key}"
  alarm_description   = "Démonstration VITALORA : ${each.key}. Consulter le tableau de bord et les journaux corrélés."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 1
  metric_name         = each.value.metric
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  dimensions          = each.value.dimensions
  treat_missing_data  = "notBreaching"
}
resource "aws_cloudwatch_dashboard" "hybrid" {
  dashboard_name = "${var.project_name}-hybrid"
  dashboard_body = jsonencode({
    start          = "-PT3H"
    periodOverride = "inherit"
    widgets = [
      { type = "alarm", x = 0, y = 0, width = 24, height = 3, properties = { title = "État de VITALORA", alarms = [for alarm in aws_cloudwatch_metric_alarm.health : alarm.arn] } },
      { type = "metric", x = 0, y = 3, width = 12, height = 6, properties = {
        title   = "Utilisation CPU EC2", region = data.aws_region.current.name, period = 300, stat = "Average",
        metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]]
      } },
      { type = "metric", x = 12, y = 3, width = 12, height = 6, properties = {
        title   = "Invocations et erreurs Lambda", region = data.aws_region.current.name, period = 60, stat = "Sum",
        metrics = [["AWS/Lambda", "Invocations", "FunctionName", var.function_name], ["AWS/Lambda", "Errors", "FunctionName", var.function_name]]
      } },
      { type = "metric", x = 0, y = 9, width = 12, height = 6, properties = {
        title   = "Échecs de traitement des commandes", region = data.aws_region.current.name, period = 60, stat = "Sum",
        metrics = [["VITALORA/Orders", "ProcessingFailures"]]
      } },
      { type = "metric", x = 12, y = 9, width = 12, height = 6, properties = {
        title   = "Messages en attente et file de lettres mortes", region = data.aws_region.current.name, period = 60, stat = "Maximum",
        metrics = [["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-order-processing"], ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-order-processing-dlq"]]
      } },
      { type = "log", x = 0, y = 15, width = 24, height = 6, properties = {
        title = "Chronologie des commandes", region = data.aws_region.current.name, view = "table",
        query = "SOURCE '${var.application_log_group}' | SOURCE '${var.worker_log_group}' | fields @timestamp, event, orderId, eventId, status | filter ispresent(orderId) | sort @timestamp desc | limit 50"
      } }
    ]
  })
}
