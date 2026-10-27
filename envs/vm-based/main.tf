module "network" {
  source = "../../modules/network"

  project_name = var.project_name
  owner_tag    = var.owner_tag
  admin_cidr   = var.admin_cidr
}

module "database" {
  source = "../../modules/database"

  project_name       = var.project_name
  owner_tag          = var.owner_tag
  private_subnet_ids = module.network.private_subnet_ids
  rds_sg_id          = module.network.rds_sg_id
}

module "compute_vm" {
  source = "../../modules/compute-vm"

  project_name      = var.project_name
  owner_tag         = var.owner_tag
  aws_region        = var.aws_region
  public_subnet_ids = module.network.public_subnet_ids
  ec2_sg_id         = module.network.ec2_sg_id
  alb_sg_id         = module.network.alb_sg_id
  instance_type     = var.instance_type
  key_name          = var.key_name

  db_endpoint           = module.database.db_endpoint
  db_name               = module.database.db_name
  db_username           = module.database.db_username
  db_password_ssm_name  = module.database.db_password_ssm_name
  assets_bucket_name    = module.database.assets_bucket_name
}
