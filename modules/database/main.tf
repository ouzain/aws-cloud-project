data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
resource "random_password" "db" {
  length  = 24
  special = false
}
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db/password"
  type  = "SecureString"
  value = random_password.db.result
}
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/${var.project_name}/db/endpoint"
  type  = "String"
  value = aws_db_instance.this.address
}
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_subnet_ids
}
resource "aws_db_instance" "this" {
  identifier                 = "${var.project_name}-db"
  engine                     = "mysql"
  engine_version             = "8.4"
  instance_class             = "db.t4g.micro"
  allocated_storage          = 20
  storage_type               = "gp3"
  storage_encrypted          = true
  db_name                    = "vitalora"
  username                   = "vitalora_admin"
  password                   = random_password.db.result
  db_subnet_group_name       = aws_db_subnet_group.this.name
  vpc_security_group_ids     = [var.rds_sg_id]
  multi_az                   = false
  publicly_accessible        = false
  auto_minor_version_upgrade = true
  backup_retention_period    = 1
  skip_final_snapshot        = true
  deletion_protection        = false
}
resource "aws_s3_bucket" "assets" {
  bucket        = "${var.project_name}-assets-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  force_destroy = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    bucket_key_enabled = true
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
  }
}
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_policy" "secure_transport" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false", "aws:PrincipalIsAWSService" = "false" } }
    }]
  })
}
resource "aws_s3_object" "products" {
  for_each               = fileset("${path.module}/../../assets", "products/**/*.svg")
  bucket                 = aws_s3_bucket.assets.id
  key                    = each.value
  source                 = "${path.module}/../../assets/${each.value}"
  source_hash            = filemd5("${path.module}/../../assets/${each.value}")
  content_type           = "image/svg+xml"
  server_side_encryption = "aws:kms"
  bucket_key_enabled     = true
}
resource "aws_s3_object" "application" {
  bucket                 = aws_s3_bucket.assets.id
  key                    = "deployments/runtime-${var.application_hash}.zip"
  source                 = var.application_zip
  source_hash            = var.application_hash
  content_type           = "application/zip"
  server_side_encryption = "aws:kms"
  bucket_key_enabled     = true
}
