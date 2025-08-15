data "aws_ami" "app_ami" {
  most_recent = true
  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["979382823631"] # Bitnami
}

module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 4.0"
  
  name = "dev"
  cidr = "10.0.0.0/16"
  
  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  
  vpc_id = module.blog_vpc.vpc_id
  name   = "blog"

  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "blog-alb"
  load_balancer_type = "application"
  vpc_id             = module.blog_vpc.vpc_id
  subnets            = module.blog_vpc.public_subnets
  security_groups    = [module.blog_sg.security_group_id]

  listeners = {
    http_listener = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "blog_tg"
      }
    }
  }

  target_groups = {
    blog_tg = {
      name_prefix      = "blog-"
      backend_protocol = "HTTP"
      backend_port     = 80
      target_type      = "instance"
    }
  }

  tags = {
    Environment = "dev"
  }
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 9.0"

  name = "blog"

  min_size            = 1
  max_size            = 2
  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   = [for tg in values(module.blog_alb.target_groups) : tg.arn]
  security_groups     = [module.blog_sg.security_group_id]
  instance_type       = var.instance_type
  image_id            = data.aws_ami.app_ami.id
}
