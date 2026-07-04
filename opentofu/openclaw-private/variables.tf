variable "aws_region" {
  description = "AWS region for the OpenClaw deployment."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Optional AWS CLI profile used by the provider."
  type        = string
  default     = "aws-dimly"
}

variable "name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "openclaw-oauth"
}

variable "openai_model" {
  description = "OpenAI model ID used after OpenAI Codex/ChatGPT OAuth login."
  type        = string
  default     = "gpt-5.3"
}

variable "openclaw_version" {
  description = "OpenClaw npm package version."
  type        = string
  default     = "2026.4.27"
}

variable "instance_type" {
  description = "EC2 instance type. c7g.large is the minimum recommended size for Slack Socket Mode plus OpenClaw gateway."
  type        = string
  default     = "c7g.large"
}

variable "enable_monitoring" {
  description = "Enable detailed EC2 monitoring and CloudWatch alarms."
  type        = bool
  default     = true
}

variable "enable_sandbox" {
  description = "Install Docker for OpenClaw sandboxed execution."
  type        = bool
  default     = true
}

variable "retain_data" {
  description = "Prevent Terraform from destroying the data EBS volume and S3 bucket."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 30
}

variable "data_volume_size" {
  description = "Persistent OpenClaw data volume size in GB."
  type        = number
  default     = 30
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Public subnet CIDR block. The instance is still private at the application layer; access is through SSM."
  type        = string
  default     = "10.0.1.0/24"
}

