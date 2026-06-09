variable "aws_region" {
  type        = string
  description = "The AWS region where the KMS key resides"
  default     = "us-east-1"
}

variable "kms_key_id" {
  type        = string
  description = "The AWS KMS Key ID or ARN used for Vault Auto-Unseal"
}

variable "db_username" {
  type        = string
  description = "Database administrative username stored in Vault"
  sensitive   = true
}

variable "db_password" {
  type        = string
  description = "Database administrative password stored in Vault"
  sensitive   = true
}