data "aws_availability_zones" "available" { state = "available" }
locals { azs = slice(data.aws_availability_zones.available.names, 0, 2) }
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.project_name}-vpc" }
}
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-igw" }
}
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-${count.index + 1}", Tier = "public" }
}
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.${count.index + 11}.0/24"
  availability_zone = local.azs[count.index]
  tags              = { Name = "${var.project_name}-private-${count.index + 1}", Tier = "private" }
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.project_name}-public-routes" }
}
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.project_name}-private-routes" }
}
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
# L’API EC2 impose des caractères ASCII dans les descriptions de groupes.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Entree HTTP publique"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }
}
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "HTTP applicatif depuis ALB et SSH administrateur facultatif"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  dynamic "ingress" {
    for_each = var.admin_cidr == null ? [] : [var.admin_cidr]
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "aws_security_group" "worker" {
  name        = "${var.project_name}-worker-sg"
  description = "Acces prive a la base pour Lambda"
  vpc_id      = aws_vpc.this.id
}
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Acces MySQL depuis EC2 et Lambda"
  vpc_id      = aws_vpc.this.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id, aws_security_group.worker.id]
  }
}
resource "aws_vpc_security_group_egress_rule" "worker_database" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.rds.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}
