variable "aws_region" {
  description = "AWS Region in which to create the backend resources."
  type        = string
  default     = "ap-south-1"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name. When null, the name is <bucket_name_prefix>-<account-id>-<region>."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.bucket_name == null || (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    )
    error_message = "bucket_name must be 3-63 characters and use only lowercase letters, numbers, periods, and hyphens."
  }
}

variable "bucket_name_prefix" {
  description = "Prefix used for the generated bucket name when bucket_name is null."
  type        = string
  default     = "terraform-state"

  validation {
    condition = (
      length(var.bucket_name_prefix) >= 3 &&
      length(var.bucket_name_prefix) <= 30 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name_prefix))
    )
    error_message = "bucket_name_prefix must be 3-30 characters and use only lowercase letters, numbers, and hyphens."
  }
}

variable "create_dynamodb_lock_table" {
  description = "Create a DynamoDB lock table for Terraform versions older than 1.10. Modern consumers should use S3 native locking."
  type        = bool
  default     = false
}

variable "dynamodb_table_name" {
  description = "Name of the optional legacy DynamoDB state-lock table."
  type        = string
  default     = "terraform-state-lock"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,255}$", var.dynamodb_table_name))
    error_message = "dynamodb_table_name must be 3-255 characters and use only letters, numbers, underscores, periods, and hyphens."
  }
}

variable "tags" {
  description = "Additional tags to merge with the standard backend tags."
  type        = map(string)
  default     = {}
}
