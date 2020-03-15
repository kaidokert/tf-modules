provider "aws" {
  region = var.aws_region
}

terraform {
  backend "s3" {}
}

module "service" {
  source = "../ecs-service"

  aws_region                    = var.aws_region
  cluster_name                  = var.cluster_name
  service_name                  = var.service_name
  service_registry_id           = var.service_registry_id
  service_registry_service_name = var.service_registry_service_name

  task_name          = "proxy"
  image              = "not used"
  cpu                = 256
  memory             = 256
  network_mode       = "bridge"
  number_of_tasks    = 1
  efs_volumes        = var.efs_volumes

  port_mappings = [
    {
      containerPort = 80
      hostPort = 0
      protocol = "tcp"
    }
  ]

  task_def_override = templatefile("${path.module}/tasks.json", {
    region                      = var.aws_region
    cluster                     = var.cluster_name
    service                     = var.service_name
    table                       = var.users_table
    realm                       = var.auth_realm
    folder                      = var.cache_dir
    duration                    = var.cache_duration
    read_only                   = var.read_only_filesystem
    mount_points                = jsonencode(var.mount_points)
  })

}