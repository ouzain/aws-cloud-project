data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# IAM — rôle d'instance en moindre privilège
# ---------------------------------------------------------------------------
# Le sns:Publish est scopé par CONVENTION DE NOMMAGE (project_name-*) plutôt
# que par ARN exact : ça découple ce module du topic SNS que Personne C
# créera en Phase 4, sans dépendance Terraform entre nos deux parties. Il lui
# suffit de nommer son topic "${var.project_name}-order-confirmation".

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name  = "${var.project_name}-ec2-role"
    Owner = var.owner_tag
  }
}

resource "aws_iam_role_policy" "ec2" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadDbSecret"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.db_password_ssm_name}"
      },
      {
        Sid      = "ReadProductImages"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.assets_bucket_name}",
          "arn:aws:s3:::${var.assets_bucket_name}/*"
        ]
      },
      {
        Sid      = "PublishOrderEvents"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${var.project_name}-*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ---------------------------------------------------------------------------
# Launch template — l'app Node.js complète est embarquée via user-data, donc
# `terraform apply` suffit à tout reconstruire de zéro (reproductibilité
# exigée en Phase 6).
# ---------------------------------------------------------------------------

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  vpc_security_group_ids = [var.ec2_sg_id]

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    package_json          = file("${path.module}/../../app/package.json")
    server_js              = file("${path.module}/../../app/server.js")
    db_host                = var.db_endpoint
    db_name                = var.db_name
    db_username             = var.db_username
    db_password_ssm_name    = var.db_password_ssm_name
    assets_bucket          = var.assets_bucket_name
    aws_region              = var.aws_region
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name  = "${var.project_name}-web"
      Owner = var.owner_tag
    }
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling Group — 2 AZ, health check via l'ALB
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = var.public_subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity

  health_check_type         = "ELB"
  health_check_grace_period = 60
  target_group_arns         = [aws_lb_target_group.web.arn]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }
  tag {
    key                 = "Owner"
    value               = var.owner_tag
    propagate_at_launch = true
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "web" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  tags = {
    Name  = "${var.project_name}-alb"
    Owner = var.owner_tag
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.selected.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
  }

  tags = {
    Name  = "${var.project_name}-tg"
    Owner = var.owner_tag
  }
}

# Le VPC id n'est pas passé en variable directe au target group : on le
# retrouve via le subnet pour éviter une variable de plus. Si tu préfères,
# ajoute `vpc_id` aux variables du module et passe-le explicitement depuis
# l'env racine.
data "aws_subnet" "first_public" {
  id = var.public_subnet_ids[0]
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.first_public.vpc_id
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
