packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

source "amazon-ebs" "proactive-engineer" {
  ami_name      = "proactive-engineer-{{timestamp}}"
  instance_type = "t3.medium"
  region        = var.aws_region

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ssh_username = "ubuntu"

  vpc_id    = var.vpc_id
  subnet_id = var.subnet_id
  associate_public_ip_address = true

  ami_description = "Proactive Engineer - pre-built with OpenClaw, Node.js 22, and the proactive-engineer skill"

  tags = {
    Name    = "proactive-engineer"
    Builder = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.proactive-engineer"]

  provisioner "shell" {
    script = "provision.sh"
  }

  provisioner "file" {
    source      = "configure-agent.sh"
    destination = "/home/ubuntu/configure-agent.sh"
  }

  provisioner "shell" {
    inline = ["chmod +x /home/ubuntu/configure-agent.sh"]
  }
}
