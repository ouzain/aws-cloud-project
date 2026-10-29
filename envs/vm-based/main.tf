data "archive_file" "application" {
  type        = "zip"
  source_dir  = "${path.module}/../../.build/runtime"
  output_path = "${path.module}/../../.build/runtime.zip"
}
module "network" {
  source       = "../../modules/network"
  project_name = var.project_name
  owner_tag    = var.owner_tag
  admin_cidr   = var.admin_cidr
}
module "database" {
  source             = "../../modules/database"
  project_name       = var.project_name
  owner_tag          = var.owner_tag
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.network.rds_sg_id
  application_zip    = data.archive_file.application.output_path
  application_hash   = data.archive_file.application.output_base64sha256
}
module "messaging" {
  source             = "../../modules/messaging"
  project_name       = var.project_name
  owner_tag          = var.owner_tag
  notification_email = var.notification_email
  private_subnet_ids = module.network.private_subnet_ids
  worker_sg_id       = module.network.worker_sg_id
  db_endpoint        = module.database.db_endpoint
  db_name            = module.database.db_name
  db_username        = module.database.db_username
  db_password        = module.database.db_password
  application_zip    = data.archive_file.application.output_path
  application_hash   = data.archive_file.application.output_base64sha256
}
module "compute_vm" {
  source               = "../../modules/compute-vm"
  project_name         = var.project_name
  owner_tag            = var.owner_tag
  aws_region           = var.aws_region
  vpc_id               = module.network.vpc_id
  public_subnet_ids    = module.network.public_subnet_ids
  ec2_sg_id            = module.network.ec2_sg_id
  alb_sg_id            = module.network.alb_sg_id
  instance_type        = var.instance_type
  desired_capacity     = var.desired_capacity
  key_name             = var.key_name
  db_endpoint          = module.database.db_endpoint
  db_name              = module.database.db_name
  db_username          = module.database.db_username
  db_password_ssm_name = module.database.db_password_ssm_name
  assets_bucket_name   = module.database.assets_bucket_name
  application_key      = module.database.application_key
  order_topic_arn      = module.messaging.topic_arn
}

module "monitoring" {
  source                    = "../../modules/monitoring"
  project_name              = var.project_name
  asg_name                  = module.compute_vm.asg_name
  function_name             = module.messaging.function_name
  worker_log_group          = module.messaging.consumer_log_group
  application_log_group     = module.compute_vm.application_log_group
  existing_audit_trail_name = var.existing_audit_trail_name
  existing_budget_name      = var.existing_budget_name
  budget_alert_email        = var.budget_alert_email
}
