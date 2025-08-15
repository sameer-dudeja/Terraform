# main.tf
# Data source for latest Bitnami Tomcat AMI
data "aws_ami" "app_ami" {
  most_recent = true
  owners      = ["979382823631"] # Bitnami
  
  filter {
    name   = "name"
    values = ["bitnami-tomcat-*-x86_64-hvm-ebs-nami"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC Module - Latest Version 5.21.0
module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = var.environment
  cidr = "10.0.0.0/16"
  
  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  
  enable_nat_gateway = false
  enable_vpn_gateway = false
  
  tags = {
    Terraform   = "true"
    Environment = var.environment
  }
}

# Security Group Module - Latest Version
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"
  
  name   = "blog-sg"
  vpc_id = module.blog_vpc.vpc_id
  
  ingress_rules       = ["https-443-tcp", "http-80-tcp", "ssh-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
  
  tags = {
    Environment = var.environment
  }
}

# Application Load Balancer Module - Latest Version 9.17.0
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.17"
  
  name               = "blog-alb"
  load_balancer_type = "application"
  vpc_id             = module.blog_vpc.vpc_id
  subnets            = module.blog_vpc.public_subnets
  security_groups    = [module.blog_sg.security_group_id]
  
  # Enable deletion protection for production
  enable_deletion_protection = false
  
  target_groups = [
    {
      name             = "blog-tg"
      backend_protocol = "HTTP"
      backend_port     = 8080  # Tomcat default port
      target_type      = "instance"
      
      health_check = {
        enabled             = true
        healthy_threshold   = 2
        interval            = 30
        matcher             = "200"
        path                = "/"
        port                = "traffic-port"
        protocol            = "HTTP"
        timeout             = 5
        unhealthy_threshold = 2
      }
    }
  ]
  
  listeners = [
    {
      port     = 80
      protocol = "HTTP"
      
      forward = {
        target_group_key = "blog-tg"
      }
    }
  ]
  
  tags = {
    Environment = var.environment
  }
}

# Auto Scaling Group Module - Latest Version
module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.10"  # Use 6.x version compatible with provider 6.x
  
  name = "blog-asg"
  
  min_size            = 1
  max_size            = 3
  desired_capacity    = 2
  vpc_zone_identifier = module.blog_vpc.public_subnets
  target_group_arns   = module.blog_alb.target_groups
  
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  launch_template_name = "blog-launch-template"
  image_id            = data.aws_ami.app_ami.id
  instance_type       = var.instance_type
  security_groups     = [module.blog_sg.security_group_id]
  
  tags = {
    Environment = var.environment
    Application = "tomcat-api"
  }
}
