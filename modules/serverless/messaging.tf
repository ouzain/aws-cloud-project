# ==========================================
# 1. TOPIC AMAZON SNS (Le point d'entrée unique)
# ==========================================
resource "aws_sns_topic" "vitalora_orders" {
  name = "vitalora-order-topic-${var.environment}"

  tags = {
    Project = "Vitalora"
    Owner   = "Amanie"
  }
}

# (Optionnel) Abonnement email direct pour la confirmation client
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.vitalora_orders.arn
  protocol  = "email"
  endpoint  = var.notification_email # Pense à définir cette variable dans ton terraform.tfvars
}


# ==========================================
# 2. FILES SQS DE TRAITEMENT (Fan-out)
# ==========================================

# Dead-Letter Queue (DLQ) pour isoler les messages en erreur (exigence Roadmap Phase 5)
resource "aws_sqs_queue" "vitalora_dlq" {
  name                      = "vitalora-orders-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14 jours maximum
}

# File SQS pour l'Audit (qui alimentera ta table DynamoDB)
resource "aws_sqs_queue" "audit_queue" {
  name                       = "vitalora-sqs-audit-${var.environment}"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.vitalora_dlq.arn
    maxReceiveCount     = 3 # Après 3 échecs, le message va dans la DLQ
  })
}

# File SQS pour la Logistique (qui alimentera CloudWatch Logs)
resource "aws_sqs_queue" "logistique_queue" {
  name                       = "vitalora-sqs-logistique-${var.environment}"
  visibility_timeout_seconds = 30
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.vitalora_dlq.arn
    maxReceiveCount     = 3
  })
}


# ==========================================
# 3. ABONNEMENTS SNS -> SQS (Le Fan-out)
# ==========================================
resource "aws_sns_topic_subscription" "audit_sub" {
  topic_arn = aws_sns_topic.vitalora_orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.audit_queue.arn
}

resource "aws_sns_topic_subscription" "logistique_sub" {
  topic_arn = aws_sns_topic.vitalora_orders.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.logistique_queue.arn
}


# ==========================================
# 4. POLITIQUES DE SÉCURITÉ SQS (Autoriser SNS à écrire dedans)
# ==========================================
resource "aws_sqs_queue_policy" "audit_queue_policy" {
  queue_url = aws_sqs_queue.audit_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSPublishToAudit"
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.audit_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.vitalora_orders.arn
          }
        }
      }
    ]
  })
}

resource "aws_sqs_queue_policy" "logistique_queue_policy" {
  queue_url = aws_sqs_queue.logistique_queue.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSNSPublishToLogistique"
        Effect    = "Allow"
        Principal = "*"
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.logistique_queue.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.vitalora_orders.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# 5. OUTPUTS (Pour que ton camarade récupère l'ARN du Topic)
# ==========================================
output "sns_topic_arn" {
  description = "ARN du Topic SNS à fournir à l'EC2 de ton camarade pour l'Étape 0"
  value       = aws_sns_topic.vitalora_orders.arn
}