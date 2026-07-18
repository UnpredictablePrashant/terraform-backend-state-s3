output "bucket_name" {
  description = "Name of the S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.tf_state.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket that stores Terraform state."
  value       = aws_s3_bucket.tf_state.arn
}

output "aws_region" {
  description = "AWS Region containing the backend resources."
  value       = var.aws_region
}

output "dynamodb_table_name" {
  description = "Name of the optional legacy DynamoDB lock table, or null when it is disabled."
  value       = try(aws_dynamodb_table.tf_lock[0].name, null)
}

output "backend_hcl_template" {
  description = "Template for a consumer backend.hcl. Replace the key with a unique path for that root module."
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.tf_state.id}"
    key          = "REPLACE_WITH_PROJECT_PATH/terraform.tfstate"
    region       = "${var.aws_region}"
    encrypt      = true
    use_lockfile = true
  EOT
}
