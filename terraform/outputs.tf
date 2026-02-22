output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.proactive_engineer.id
}

output "public_ip" {
  description = "Public IP of the instance"
  value       = aws_instance.proactive_engineer.public_ip
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = var.ssh_public_key != "" ? "ssh ubuntu@${aws_instance.proactive_engineer.public_ip}" : "No SSH key provided — use EC2 Instance Connect"
}

output "status_check" {
  description = "Command to check agent status via SSH"
  value       = "ssh ubuntu@${aws_instance.proactive_engineer.public_ip} 'openclaw --profile pe-${var.agent_name} gateway status'"
}
