variable "aws_region" {
  description = "AWS region to deploy in"
  type        = string
  default     = "us-east-1"
}

variable "ami_id" {
  description = "Pre-built Proactive Engineer AMI ID (from packer build). Leave empty to use stock Ubuntu."
  type        = string
  default     = "ami-0e42d1722f689a03f"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instance (leave empty to skip key pair creation)"
  type        = string
  default     = ""
}

variable "slack_app_token" {
  description = "Slack App Token (xapp-...)"
  type        = string
  sensitive   = true
}

variable "slack_bot_token" {
  description = "Slack Bot Token (xoxb-...)"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token (ghp_...)"
  type        = string
  sensitive   = true
}

variable "gemini_api_key" {
  description = "Google Gemini API Key"
  type        = string
  sensitive   = true
}

variable "agent_name" {
  description = "Short identifier for this agent"
  type        = string
  default     = "default"
}

variable "agent_display_name" {
  description = "How this agent appears in Slack messages"
  type        = string
  default     = "Proactive Engineer"
}

variable "vpc_id" {
  description = "VPC ID to launch the instance in (required if no default VPC)"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance in (required if no default VPC)"
  type        = string
  default     = ""
}
