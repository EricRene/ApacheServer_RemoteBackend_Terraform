terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }

  backend "s3"{

  }
}

/////////////////////////////////////
// ------------ Data ------------ //
///////////////////////////////////

data "aws_availability_zones" "available" {
  state = "available"
}

output "alb_sg_id" {
    value = aws_security_group.alb_sg.id
}

output "web_server_sg_id" {
    value = aws_security_group.web_server_sg.id
}

output "alb_arn" {
    value = aws_lb.my_alb.arn
}

//////////////////////////////////////////
// ------------ Variables ------------ //
////////////////////////////////////////

variable "aws_access_key" {}

variable "aws_secret_key" {}

variable "region" {}

variable "vpc_cidr" {}

variable "public_subnet_names" {
  type = list(string)
  default = [
    "Public Subnet 1",
    "Public Subnet 2"
  ]
}

/////////////////////////////////////////
// ------------ Provider ------------ //
///////////////////////////////////////

provider "aws" {
  profile    = "default"
  region     = var.region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  skip_credentials_validation = true
}

////////////////////////////////////
// ------------ VPC ------------ //
//////////////////////////////////

resource "aws_vpc" "my_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = "false"

  tags = {
    Name = "Task 9 VPC"
  }
}

//////////////////////////////////////////////////
// ------------ Internet Gateway ------------ //
//////////////////////////////////////////////

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "Task 9 Internet Gateway"
  }
}

//////////////////////////////////////////////
// ------------ Route Tables ------------ //
//////////////////////////////////////////

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "Public_route_table"
  }
}

////////////////////////////////////////
// ------------ Subnets ------------ //
//////////////////////////////////////

resource "aws_subnet"  "public_subnets" {
  count                   = 2

  cidr_block              = "192.168.${count.index}.0/24"
  vpc_id                  = aws_vpc.my_vpc.id
  map_public_ip_on_launch = "true"
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = tomap({ "Name" = "${var.public_subnet_names[count.index]}" })
}

////////////////////////////////////////////////////////
// ------------ Route Table Association ------------ //
//////////////////////////////////////////////////////

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = "${aws_subnet.public_subnets.*.id[count.index]}"
  route_table_id = aws_route_table.public_route_table.id
}

////////////////////////////////////////////////
// ------------ Security Groups ------------ //
//////////////////////////////////////////////

resource "aws_security_group" "alb_sg" {
  name        = "ALB-SG"
  description = "Application load balancer security group"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description      = "Allows https requests"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "web_server_sg" {
  name        = "Web-Server-SG"
  description = "Web Server security group"
  vpc_id      = aws_vpc.my_vpc.id

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

}

resource "aws_security_group_rule" "web_server_sg_rule" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.web_server_sg.id
  source_security_group_id = aws_security_group.alb_sg.id
}

//////////////////////////////////////////////////////
// ------------ Elastic Load Balancer ------------ //
////////////////////////////////////////////////////

resource "aws_lb" "my_alb" {
  name               = "Task-9-ALB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for subnet in aws_subnet.public_subnets : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

resource "aws_lb_target_group" "my_target_group" {
  name     = "Task-9-Target-Group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}

//////////////////////////////////////////
// ------------ Instances ------------ //
////////////////////////////////////////

resource "aws_instance" "web" {
  ami                    = "ami-001089eb624938d9f"
  instance_type          = "t2.micro"
  subnet_id              = "aws_subnet.public_subnets[0].id"
  vpc_security_group_ids = ["${aws_security_group.web_server_sg.id}"]
  key_name               = "Task-9-KP"


  user_data = <<EOF
#!/bin/bash
sudo apt-get update -y
sudo apt-get install apache2 unzip -y
echo '<html><center><body bgcolor="black" text="#39ff14" style="font-family: Arial"><h1>Load Balancer Demo</h1><h3>This is a test container! > /var/www/html/index.html
curl http://169.254.169.254/latest/meta-data/placement/availability-zone >> /var/www/html/index.html
echo '</h3> <h3>Instance Id: ' >> /var/www/html/index.html
curl http://169.254.169.254/latest/meta-data/instance-id >> /var/www/html/index.html
echo '</h3> <h3>Public IP: ' >> /var/www/html/index.html
curl http://169.254.169.254/latest/meta-data/public-ipv4 >> /var/www/html/index.html
echo '</h3> <h3>Local IP: ' >> /var/www/html/index.html
curl http://169.254.169.254/latest/meta-data/local-ipv4 >> /var/www/html/index.html
echo '</h3></html> ' >> /var/www/html/index.html

EOF

  tags = {
    Name = "Task-9-Instance"
  }
}
