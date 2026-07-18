data "aws_caller_identity" "current" {}

locals {
  generated_bucket_name = "${var.bucket_name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  state_bucket_name     = coalesce(var.bucket_name, local.generated_bucket_name)

  common_tags = merge(
    {
      Name      = local.state_bucket_name
      ManagedBy = "Terraform"
      Purpose   = "Terraform remote state"
    },
    var.tags
  )
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket_name
  tags   = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "require_tls" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*"
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "require_tls" {
  bucket = aws_s3_bucket.tf_state.id
  policy = data.aws_iam_policy_document.require_tls.json

  depends_on = [aws_s3_bucket_public_access_block.tf_state]
}

# DynamoDB locking is retained only for consumers running older Terraform versions.
resource "aws_dynamodb_table" "tf_lock" {
  count = var.create_dynamodb_lock_table ? 1 : 0

  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(local.common_tags, { Name = var.dynamodb_table_name })
}
