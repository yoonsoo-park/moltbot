output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.openclaw.id
}

output "gateway_token_command" {
  description = "Command to retrieve the OpenClaw gateway token."
  value       = "aws ssm get-parameter --profile ${var.aws_profile} --region ${var.aws_region} --name ${aws_ssm_parameter.gateway_token.name} --with-decryption --query Parameter.Value --output text"
}

output "port_forward_command" {
  description = "Run locally to access the private Gateway UI."
  value       = "aws ssm start-session --profile ${var.aws_profile} --region ${var.aws_region} --target ${aws_instance.openclaw.id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"18789\"],\"localPortNumber\":[\"18789\"]}'"
}

output "gateway_url" {
  description = "Gateway URL after port forwarding. Replace <token> with gateway_token_command output."
  value       = "http://localhost:18789/?token=<token>"
}

output "openai_oauth_commands" {
  description = "Commands to complete OpenAI OAuth on the instance."
  value       = <<-EOT
    aws ssm start-session --profile ${var.aws_profile} --region ${var.aws_region} --target ${aws_instance.openclaw.id}
    sudo -iu ubuntu
    openclaw models auth login --provider openai-codex
    openclaw models status --probe
    systemctl --user restart openclaw-gateway
  EOT
}

output "openai_model" {
  description = "Configured OpenAI model."
  value       = var.openai_model
}

output "data_volume_id" {
  description = "Persistent data volume ID."
  value       = aws_ebs_volume.data.id
}

output "data_bucket_name" {
  description = "Persistent data bucket name."
  value       = aws_s3_bucket.data.id
}

