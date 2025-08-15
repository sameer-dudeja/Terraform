############################
# AMI lookup (Bitnami Tomcat)
############################
data "aws_ami" "blog_app_ami" {
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

############
# VPC
############
module "blog_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "blog-dev"
  cidr = "10.0.0.0/16"

  azs            = ["${var.aws_region}a","${var.aws_region}b","${var.aws_region}c"]
  public_subnets = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Terraform   = "true"
    Environment = "dev"
    Project     = "blog"
  }
}

#################
# Security Group
#################
module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"

  name   = "blog-sg"
  vpc_id = module.blog_vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules       = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]

  tags = {
    Environment = "dev"
    Project     = "blog"
  }
}

########
# ALB
########
module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.10.0"

  name               = "alb-blog"
  load_balancer_type = "application"

  vpc_id          = module.blog_vpc.vpc_id
  subnets         = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]

  # HTTP listener that redirects to HTTPS (if HTTPS is added later)
  listeners = {
    blog-http-https-redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  # HTTP target group for instances on port 80
  target_groups = {
    blog-tg = {
      name_prefix = "blog"
      protocol    = "HTTP"
      port        = 80
      target_type = "instance"

      health_check = {
        protocol            = "HTTP"
        path                = "/"
        interval            = 30
        timeout             = 5
        healthy_threshold   = 2
        unhealthy_threshold = 2
        matcher             = "200-399"
      }
    }
  }

  tags = {
    Environment = "dev"
    Project     = "blog"
  }
}

###################################
# Auto Scaling Group + Launch Template
###################################
module "blog_asg" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "7.7.0"

  name                      = "blog-asg"
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 1
  health_check_type         = "EC2"
  vpc_zone_identifier       = module.blog_vpc.public_subnets
  wait_for_capacity_timeout = 0

  # Attach to ALB target group
  target_group_arns = [module.blog_alb.target_groups["blog-tg"].arn]

  # Launch template details
  launch_template_name        = "blog-lt"
  launch_template_description = "Launch template for blog app"
  update_default_version      = true

  image_id       = data.aws_ami.blog_app_ami.id
  instance_type  = var.instance_type
  ebs_optimized  = true
  enable_monitoring = true

  # Enforce IMDSv2
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Network interface and security group
  network_interfaces = [
    {
      delete_on_termination = true
      description           = "primary"
      device_index          = 0
      security_groups       = [module.blog_sg.security_group_id]
    }
  ]

  # Root volume
  block_device_mappings = [
    {
      device_name = "/dev/xvda"
      ebs = {
        delete_on_termination = true
        encrypted             = true
        volume_size           = 20
        volume_type           = "gp3"
      }
    }
  ]

  # Optional: example target-tracking policy
  # scaling_policies = {
  #   cpu-target = {
  #     policy_type = "TargetTrackingScaling"
  #     target_tracking_configuration = {
  #       predefined_metric_specification = {
  #         predefined_metric_type = "ASGAverageCPUUtilization"
  #       }
  #       target_value = 50.0
  #     }
  #   }
  # }

  tags = {
    Name        = "blog-asg"
    Environment = "dev"
    Project     = "blog"
  }
}
