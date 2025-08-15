data "aws_ami" "app_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = [var.ami_filter.name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [var.ami_filter.owner]
}

data "aws_vpc" "default"{
  default = true
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.environment.name
  cidr = "${var.environment.network_prefix}.0.0/16"

  azs             = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
  public_subnets  = ["${var.environment.network_prefix}.101.0/24", "${var.environment.network_prefix}.102.0/24", "${var.environment.network_prefix}.103.0/24"]

  tags = {
    Terraform = "true"
    Environment = var.environment.name
  }
}

resource "aws_instance" "blog" {
  ami           = data.aws_ami.app_ami.id
  instance_type = var.instance_type

  vpc_security_group_ids = [module.blog_sg.security_group_id]

  subnet_id = module.blog_vpc.public_subnets[0]

  tags = {
    Name = "Learning Terraform"
  }
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.0.1"

  name                = "${var.environment.name}-blog-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = module.blog_vpc.public_subnets
  security_groups     = [module.blog_sg.security_group_id]

  traffic_source_attachments = {
    alb = {
      traffic_source_identifier = module.blog_alb.target_groups["blog"].arn
      type                      = "elbv2"
    }
  }

  image_id      = data.aws_ami.app_ami.id
  instance_type = var.instance_type
}


module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "9.17.0"

  name = "${var.environment.name}-blog-alb"
  vpc_id = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets
  security_groups = [module.blog_sg.security_group_id]

  listeners = {
    http = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "blog"
      }
    }
  }

  target_groups = {
    blog = {
      name_prefix = "${var.environment.name}-"
      protocol    = "HTTP"
      port        = 80
      create_attachment = false
      # NO 'target_type' or 'targets' here
    }
  }

  tags = {
    Environment = var.environment.name
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.3.0"
  name    = "${var.environment.name}-blog"

  vpc_id      = module.blog_vpc.vpc_id

  ingress_rules = ["http-80-tcp","https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]

  egress_rules = ["all-all"]
  egress_cidr_blocks = ["0.0.0.0/0"]
}