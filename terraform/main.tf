module "vpc" {
  source = "./modules/vpc"
}


module "sg" {
  source        = "./modules/sg"
  vpc_id        = module.vpc.vpc_id
  ecs_task_port = var.ecs_task_port
}

module "alb" {
  source            = "./modules/alb"
  alb_sg_id         = module.sg.alb_sg_id
  vpc_id            = module.vpc.vpc_id
  ecs_task_port     = var.ecs_task_port
  alb_subnet_public = [module.vpc.ecs_subnet_public_2a_id, module.vpc.ecs_subnet_public_2b_id]
}

module "acm" {
  source           = "./modules/acm"
  ecs_alb_dns_name = module.alb.ecs_alb_dns_name
  ecs_alb_zone_id  = module.alb.ecs_alb_zone_id
}

module "ecs" {
  source                   = "./modules/ecs"
  ecs_alb_target_group_arn = module.alb.target_group_arn
  ecs_service_sg_id        = module.sg.ecs_service_sg_id
  ecs_subnet_private_2a_id = module.vpc.ecs_subnet_private_2a_id
  ecs_subnet_private_2b_id = module.vpc.ecs_subnet_private_2b_id
  ecs_task_port            = var.ecs_task_port
}
