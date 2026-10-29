output "db_endpoint" {
  value = aws_db_instance.this.address
}

output "db_port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "db_username" {
  value = aws_db_instance.this.username
}

output "db_password_ssm_name" {
  value = aws_ssm_parameter.db_password.name
}

output "assets_bucket_name" {
  value = aws_s3_bucket.assets.bucket
}

output "application_key" {
  value = aws_s3_object.application.key
}

output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
