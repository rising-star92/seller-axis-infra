terraform {
  required_providers { aws = "~> 3.60" }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

terraform {
  backend "s3" {
    bucket = "stage-selleraxis-state-terraform"
    key    = "environments/us-east-1-stage/website/terraform.tfstate"
    region = "us-east-1"
  }
}

module "vpc" {
  environment_name         = var.environment_name
  source                   = "../../../modules/vpc"
  vpc_name                 = var.vpc_name
  vpc_cidr_block           = var.vpc_cidr_block
  availability_zones       = var.availability_zones
  public_subnet_cidr_block = var.public_subnet_cidr_block
}

module "iam_role" {
  environment_name              = var.environment_name
  source                        = "../../../modules/iam_role"
  iam_role_name                 = var.iam_role_name
  aws_iam_instance_profile_name = var.aws_iam_instance_profile_name
  aws_iam_role_policy_name      = var.aws_iam_role_policy_name
}

module "security_group" {
  environment_name                      = var.environment_name
  source                                = "../../../modules/security_group"
  vpc_id                                = module.vpc.vpc_id
  vpc_cidr_blocks                       = [module.vpc.vpc_cidr_blocks]
  security_group_name                   = var.security_group_name
  security_group_description            = var.security_group_description
  security_group_http_cidr_blocks       = var.security_group_http_cidr_blocks
  security_group_http_ipv6_cidr_blocks  = var.security_group_http_ipv6_cidr_blocks
  security_group_https_cidr_blocks      = var.security_group_https_cidr_blocks
  security_group_https_ipv6_cidr_blocks = var.security_group_https_ipv6_cidr_blocks
  security_group_ssh_cidr_blocks        = var.security_group_ssh_cidr_blocks
}

resource "aws_security_group" "rds_sg" {
  name        = "${var.rds_security_group_name}-${var.environment_name}"
  description = "${var.rds_security_group_description}-${var.environment_name}"

  vpc_id = module.vpc.vpc_id

  ingress {
    from_port = 5432
    to_port   = 5432
    protocol  = "tcp"

    cidr_blocks = [module.vpc.vpc_cidr_blocks]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "rds" {
  environment_name                = var.environment_name
  source                          = "../../../modules/rds"
  allocated_storage               = var.allocated_storage
  storage_type                    = var.storage_type
  engine                          = var.engine
  engine_version                  = var.engine_version
  instance_class                  = var.instance_class
  db_name                         = var.db_name
  username                        = var.username
  password                        = var.password
  database_authentication_enabled = var.database_authentication_enabled
  backup_retention_period         = var.backup_retention_period
  security_group_ids              = [aws_security_group.rds_sg.id]
  subnet_ids                      = concat(module.vpc.subnet_ids)
}

module "ecs" {
  environment_name = var.environment_name
  source           = "../../../modules/ecs"
  ecs_cluster_name = var.ecs_cluster_name
}

module "ecr" {
  environment_name = var.environment_name
  source           = "../../../modules/ecr"
  ecr_name         = var.ecr_name
  mutability       = var.mutability
  scan_on_push     = var.scan_on_push
}

module "acm_certificate" {
  environment_name      = var.environment_name
  source                = "../../../modules/acm_certificate"
  domain_name           = var.domain_name
  validation_method     = var.validation_method
  create_before_destroy = var.create_before_destroy
}

module "load_balancing" {
  environment_name    = var.environment_name
  source              = "../../../modules/load_balancing"
  alb_name            = var.alb_name
  lb_target_group     = var.lb_target_group
  security_group_ids  = [module.security_group.id]
  subnet_ids          = module.vpc.subnet_ids
  vpc_id              = module.vpc.vpc_id
  acm_certificate_arn = module.acm_certificate.acm_certificate_arn
  health_check_path   = "/api/health"
}

module "cloudwatch_log" {
  source                    = "../../../modules/cloudwatch_log"
  cloudwatch_log_group_name = var.cloudwatch_log_group_name
  environment_name          = var.environment_name
}

module "ecs_service" {
  environment_name                          = var.environment_name
  source                                    = "../../../modules/ecs_service"
  vpc_id                                    = module.vpc.vpc_id
  iam_role_arn                              = module.iam_role.iam_role_arn
  ecs_cluster_id                            = module.ecs.ecs_cluster_id
  repository_url                            = module.ecr.repository_url
  aws_lb_target_group_arn                   = module.load_balancing.aws_lb_target_group_arn
  ecs_service_private_namespace_name        = var.ecs_service_private_namespace_name
  ecs_service_private_namespace_description = var.ecs_service_private_namespace_description
  ecs_service_name                          = var.ecs_service_name
  container_name                            = var.container_name
  container_port                            = var.container_port
  subnet_ids                                = module.vpc.subnet_ids
  security_group_ids                        = [module.security_group.id]
  aws_region                                = var.aws_region
  cloudwatch_log_group_name                 = module.cloudwatch_log.name
  ecs_cluster_name                          = var.ecs_cluster_name
  task_family_name                          = var.task_family_name
  ecs_task_policy_name                      = var.ecs_task_policy_name
  ecs_task_role_name                        = var.ecs_task_role_name
}

module "s3" {
  environment_name        = var.environment_name
  source                  = "../../../modules/s3"
  photo_video_bucket_name = var.photo_video_bucket_name
  photo_video_bucket_acl  = var.photo_video_bucket_acl
}




module "lambdas" {
  environment_name                 = var.environment_name
  source                           = "../../../modules/lambdas"
  acknowledge_forward_handler_name = var.acknowledge_forward_handler_name
  acknowledge_sqs_name             = var.acknowledge_sqs_name
  lambda_secret                    = var.lambda_secret
  api_host                         = "https://${var.domain_name}"
}

module "lambda_update_inventory" {
  environment_name              = var.environment_name
  update_inventory_handler_name = var.update_inventory_handler_name
  source                        = "../../../modules/lambda_update_inventory"
  update_inventory_sqs_name     = var.update_inventory_sqs_name
  api_host                      = "https://${var.domain_name}/api/product-warehouse-static-data/update-inventory"
  lambda_secret                 = "111"
}
module "lambda_trigger_crud_product_quickbook_online" {
  environment_name                              = var.environment_name
  trigger_crud_product_quickbook_online_name    = var.trigger_crud_product_quickbook_online_name
  source                                        = "../../../modules/lambda_trigger_crud_product_quickbook_online"
  crud_product_sqs_name                         = var.crud_product_sqs_name
  api_host                                      = "https://${var.domain_name}/api/products/quickbook"
  lambda_secret                                 = "111"
}
module "lambda_trigger_crud_retailer_quickbook_online" {
  environment_name                              = var.environment_name
  trigger_crud_retailer_quickbook_online_name    = var.trigger_crud_retailer_quickbook_online_name
  source                                        = "../../../modules/lambda_trigger_crud_retailer_quickbook_online"
  crud_retailer_sqs_name                         = var.crud_retailer_sqs_name
  api_host                                      = "https://${var.domain_name}/api/retailers/quickbook"
  lambda_secret                                 = "111"
}
module "lambda_update_retailer_inventory" {
  environment_name                              = var.environment_name
  update_retailer_inventory_handler_name        = var.update_retailer_inventory_handler_name
  source                                        = "../../../modules/lambda_update_retailer_inventory"
  update_retailer_inventory_sqs_name            = var.update_retailer_inventory_sqs_name
  update_individual_retailer_inventory_sqs_name = var.update_individual_retailer_inventory_sqs_name
  api_host                                      = "https://${var.domain_name}/api/retailers/"
  lambda_secret                                 = "111"
}

module "lambda_update_individual_retailer_inventory" {
  environment_name                                  = var.environment_name
  update_individual_retailer_inventory_handler_name = var.update_individual_retailer_inventory_handler_name
  update_individual_retailer_inventory_sqs_name     = var.update_individual_retailer_inventory_sqs_name
  source                                            = "../../../modules/lambda_update_individual_retailer_inventory"
  api_host                                          = "https://${var.domain_name}/api/retailers/"
  lambda_secret                                     = "111"
}

module "lambda_update_inventory_to_commercehub" {
  source = "../../../modules/lambda_update_inventory_to_commercehub"
  environment_name = var.environment_name
  update_inventory_to_commercehub_handler_name = var.update_inventory_to_commercehub_handler_name
  update_inventory_to_commercehub_sqs_name = var.update_inventory_to_commercehub_sqs_name
  api_host = "https://${var.domain_name}/api"
  lambda_secret = "111"
}

module "lambda_qbo_unhandled_data_handler" {
  source = "../../../modules/lambda_qbo_unhandled_data"
  environment_name = var.environment_name
  qbo_unhandled_data_handler_name = var.qbo_unhandled_data_handler_name
  qbo_unhandled_data_sqs_name = var.qbo_unhandled_data_sqs_name
  api_host = "https://${var.domain_name}/api"
  lambda_secret = "111"
}
# module "ses" {
#   source                          = "../../../modules/ses"
# }

module "lambda_error_log_handler" {
  source              = "../../../modules/lambda_error_log_handler"
  environment_name    = var.environment_name
  lambda_name         = var.error_log_handler_name
  slack_webhook_host  = var.slack_webhook_host
  cloudwatch_log_name = module.cloudwatch_log.name
  cloudwatch_log_arn  = module.cloudwatch_log.arn
  aws_region          = var.aws_region
}

module "lambda_health_check_fail_handler" {
  source                  = "../../../modules/lambda_health_check_fail_handler"
  environment_name        = var.environment_name
  lambda_name             = var.health_check_fail_handler_name
  slack_webhook_host      = var.slack_webhook_host
  aws_region              = var.aws_region
  alarm_metric_name       = var.alarm_metric_name
  sns_name                = var.health_check_fail_sns_name
  target_group_arn_suffix = module.load_balancing.target_group_arn_suffix
  lb_arn_suffix           = module.load_balancing.lb_arn_suffix
}

module "get_new_order_handler" {
  source                          = "../../../modules/schedule_getting_order"
  environment_name                = var.environment_name
  get_new_order_handle_name       = var.get_new_order_handle_name
  get_new_order_name              = var.get_new_order_name
  trigger_get_new_order_name      = var.trigger_get_new_order_name
  api_host                        = "https://${var.domain_name}/api/retailer-purchase-orders/import-by-group-retailers"
  lambda_secret                   = var.stag_lambda_secret
  retailer_getting_order_sqs_name = var.retailer_getting_order_sqs_name
}
