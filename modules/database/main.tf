# ---------------------------------------------------------------------------
# Mot de passe généré, jamais en dur dans le code ni dans le state en clair
# côté app : l'EC2 le récupère au boot via SSM Parameter Store (SecureString),
# chiffré avec la clé KMS gérée par AWS (aws/ssm) — gratuite, contrairement à
# une clé client (1 $/mois).
# ---------------------------------------------------------------------------

resource "random_password" "db" {
  length  = 20
  special = false # évite les caractères qui cassent les chaînes de connexion
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db/password"
  type  = "SecureString"
  value = random_password.db.result

  tags = {
    Name  = "${var.project_name}-db-password"
    Owner = var.owner_tag
  }
}

resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/${var.project_name}/db/endpoint"
  type  = "String"
  value = aws_db_instance.this.address

  tags = {
    Name  = "${var.project_name}-db-endpoint"
    Owner = var.owner_tag
  }
}

# ---------------------------------------------------------------------------
# RDS — single-AZ, chiffré avec la clé KMS par défaut (aws/rds, gratuite)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name  = "${var.project_name}-db-subnets"
    Owner = var.owner_tag
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true # clé KMS par défaut aws/rds, pas de frais de clé

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_sg_id]

  multi_az                = false # Multi-AZ = palier "illustration", hors budget (voir roadmap)
  publicly_accessible     = false
  backup_retention_period = 1
  skip_final_snapshot     = true # projet académique : on veut pouvoir `destroy` sans friction
  deletion_protection     = false

  tags = {
    Name  = "${var.project_name}-db"
    Owner = var.owner_tag
  }
}

# ---------------------------------------------------------------------------
# S3 — visuels du catalogue produits
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-assets-${var.owner_tag}"

  tags = {
    Name  = "${var.project_name}-assets"
    Owner = var.owner_tag
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3, gratuit (pas de clé KMS client)
    }
  }
}

# Les images produits sont publiques en lecture (catalogue consultable sans
# authentification) mais rien d'autre dans le bucket ne l'est : la policy ne
# cible que le préfixe /products/*. En production, on passerait par
# CloudFront + OAC plutôt qu'un accès public direct (voir le palier
# "illustration" du roadmap).
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "assets_public_read" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "PublicReadProductImages"
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.assets.arn}/products/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.assets]
}
