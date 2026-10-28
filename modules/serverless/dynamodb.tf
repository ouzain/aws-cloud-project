# Table DynamoDB pour l'audit et le reporting des commandes Vitalora
resource "aws_dynamodb_table" "vitalora_orders" {
  name         = "vitalora-orders-${var.environment}"
  billing_mode = "PAY_PER_REQUEST" 

  # Clés du modèle Single-Table exigé par la roadmap
  hash_key  = "PK" # Partition Key (ex: ORDER#ORD-101)
  range_key = "SK" # Sort Key      (ex: ITEM#PROD-MAG-01)

  attribute {
    name = "PK"
    type = "S" # String
  }

  attribute {
    name = "SK"
    type = "S" # String
  }

  # Chiffrement au repos obligatoire (Règle Free Tier : utiliser la clé gérée par AWS pour éviter les frais de 1$/mois)
  server_side_encryption {
    enabled     = true
  }

  tags = {
    Project = "Vitalora"
    Owner   = "Amanie" # Tag d'identification pour la gouvernance budgétaire
    Tier    = "Serverless"
  }
}

# Output indispensable pour que tes futures fonctions Lambda connaissent le nom de la table
output "dynamodb_table_name" {
  value = aws_dynamodb_table.vitalora_orders.name
}