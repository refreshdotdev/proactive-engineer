terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "proactive_engineer" {
  name_prefix = "proactive-engineer-"
  description = "Security group for Proactive Engineer agent"
  vpc_id      = var.vpc_id != "" ? var.vpc_id : null

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
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
    Name = "proactive-engineer"
  }
}

resource "aws_key_pair" "proactive_engineer" {
  count      = var.ssh_public_key != "" ? 1 : 0
  key_name   = "proactive-engineer"
  public_key = var.ssh_public_key
}

resource "aws_instance" "proactive_engineer" {
  ami                         = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  vpc_security_group_ids      = [aws_security_group.proactive_engineer.id]
  key_name                    = var.ssh_public_key != "" ? aws_key_pair.proactive_engineer[0].key_name : null
  subnet_id                   = var.subnet_id != "" ? var.subnet_id : null
  associate_public_ip_address = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user-data.sh", {
    slack_app_token    = var.slack_app_token
    slack_bot_token    = var.slack_bot_token
    github_token       = var.github_token
    gemini_api_key     = var.gemini_api_key
    agent_name         = var.agent_name
    agent_display_name = var.agent_display_name
  })

  tags = {
    Name = "proactive-engineer-${var.agent_name}"
  }
}
