terraform {
  required_version = ">= 1.10.0"

  # Values are supplied by backend.hcl during terraform init.
  backend "s3" {}
}
