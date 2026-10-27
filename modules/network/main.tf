# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
# Choix budgétaire volontaire : pas de NAT Gateway (jamais couvert par le Free
# Tier, facturé à l'heure + au Go — voir la section "Gouvernance budgétaire"
# du roadmap). L'EC2 vit donc dans un subnet PUBLIC, protégé uniquement par
# son Security Group (ingress HTTP depuis l'ALB, SSH depuis mon IP). RDS reste
# dans un subnet PRIVÉ, inatteignable depuis Internet.

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name  = "${var.project_name}-vpc"
    Owner = var.owner_tag
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name  = "${var.project_name}-igw"
    Owner = var.owner_tag
  }
}

# --- Subnets publics (ALB + EC2) --------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name  = "${var.project_name}-public-${var.azs[count.index]}"
    Owner = var.owner_tag
    Tier  = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name  = "${var.project_name}-public-rt"
    Owner = var.owner_tag
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# --- Subnets privés (RDS uniquement) ----------------------------------------

resource "aws_subnet" "private" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name  = "${var.project_name}-private-${var.azs[count.index]}"
    Owner = var.owner_tag
    Tier  = "private"
  }
}

# Table de routage locale uniquement (pas de 0.0.0.0/0, pas de NAT) : ces
# subnets n'ont aucune route vers Internet, par construction.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name  = "${var.project_name}-private-rt"
    Owner = var.owner_tag
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Security Groups — moindre privilège, chaînés entre eux
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "ALB : HTTP public uniquement"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP depuis Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.project_name}-alb-sg"
    Owner = var.owner_tag
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "EC2 : HTTP depuis l'ALB uniquement + SSH depuis l'IP admin"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP depuis l'ALB"
    from_port       = 3000
    to_port          = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH depuis l'IP admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.project_name}-ec2-sg"
    Owner = var.owner_tag
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "RDS : accessible uniquement depuis l'EC2"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "MySQL depuis l'EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name  = "${var.project_name}-rds-sg"
    Owner = var.owner_tag
  }
}
