# ==========================================
# 0. GROUPES DE JOURNAUX CLOUDWATCH EXPLICITES
# ==========================================
resource "aws_cloudwatch_log_group" "lambda_audit_logs" {
  name              = "/aws/lambda/vitalora-audit-${var.environment}"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "lambda_logistique_logs" {
  name              = "/aws/lambda/vitalora-logistique-${var.environment}"
  retention_in_days = 7
}


# ==========================================
# 1. ARCHIVAGE DU CODE (ZIP automatique)
# ==========================================
data "archive_file" "lambda_audit_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/lambda-audit"
  output_path = "${path.module}/files/lambda-audit.zip"
}

data "archive_file" "lambda_logistique_zip" {
  type        = "zip"
  source_dir  = "${path.module}/src/lambda-logistique"
  output_path = "${path.module}/files/lambda-logistique.zip"
}


# ==========================================
# 2. RÔLES IAM (Least Privilege)
# ==========================================

# --- Rôle Lambda Audit ---
resource "aws_iam_role" "lambda_audit_role" {
  name = "vitalora-lambda-audit-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attache la politique officielle AWS pour CloudWatch Logs
resource "aws_iam_role_policy_attachment" "audit_logs_policy" {
  role       = aws_iam_role.lambda_audit_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_audit_policy" {
  name = "vitalora-lambda-audit-policy"
  role = aws_iam_role.lambda_audit_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.audit_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.vitalora_orders.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- Rôle Lambda Logistique ---
resource "aws_iam_role" "lambda_logistique_role" {
  name = "vitalora-lambda-logistique-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Attache la politique officielle AWS pour CloudWatch Logs
resource "aws_iam_role_policy_attachment" "logistique_logs_policy" {
  role       = aws_iam_role.lambda_logistique_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_logistique_policy" {
  name = "vitalora-lambda-logistique-policy"
  role = aws_iam_role.lambda_logistique_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.logistique_queue.arn
      }
    ]
  })
}


# ==========================================
# 3. CRÉATION DES FONCTIONS LAMBDA
# ==========================================
resource "aws_lambda_function" "lambda_audit" {
  filename         = data.archive_file.lambda_audit_zip.output_path
  function_name    = "vitalora-audit-${var.environment}"
  role             = aws_iam_role.lambda_audit_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_audit_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.vitalora_orders.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_audit_logs,
    aws_iam_role_policy_attachment.audit_logs_policy
  ]
}

resource "aws_lambda_function" "lambda_logistique" {
  filename         = data.archive_file.lambda_logistique_zip.output_path
  function_name    = "vitalora-logistique-${var.environment}"
  role             = aws_iam_role.lambda_logistique_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.lambda_logistique_zip.output_base64sha256

  depends_on = [
    aws_cloudwatch_log_group.lambda_logistique_logs,
    aws_iam_role_policy_attachment.logistique_logs_policy
  ]
}


# ==========================================
# 4. CONNEXION SQS -> LAMBDA (Event Source Mapping)
# ==========================================
resource "aws_lambda_event_source_mapping" "audit_mapping" {
  event_source_arn = aws_sqs_queue.audit_queue.arn
  function_name    = aws_lambda_function.lambda_audit.arn
  batch_size       = 5
}

resource "aws_lambda_event_source_mapping" "logistique_mapping" {
  event_source_arn = aws_sqs_queue.logistique_queue.arn
  function_name    = aws_lambda_function.lambda_logistique.arn
  batch_size       = 5
}