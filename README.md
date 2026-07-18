# Terraform S3 Backend Bootstrap

This standalone Terraform root module creates an S3 remote-state backend that other Terraform root modules can consume.

Running `terraform init`, `terraform plan`, and `terraform apply` in this directory creates:

- A private S3 bucket for Terraform state.
- S3 bucket versioning for state recovery.
- Server-side encryption with Amazon S3 managed keys (`AES256`).
- S3 Object Ownership set to `BucketOwnerEnforced`.
- A complete S3 public-access block.
- A bucket policy that denies requests that do not use TLS.
- Native S3 state-locking support through the consumer's `use_lockfile = true` setting.
- Optionally, a DynamoDB lock table for Terraform versions older than 1.10.

The bootstrap intentionally uses local state when it first runs. An S3 backend cannot be used until the bucket that implements it exists. Do not commit the bootstrap's `terraform.tfstate`; keep it secure because it records the backend resources.

## Prerequisites

- Terraform 1.10 or later.
- AWS credentials available through the AWS CLI profile, environment variables, an IAM role, or another standard AWS credential source.
- Permission to read the current AWS account identity and create/manage the S3 resources in this module.
- If legacy locking is enabled, permission to create/manage a DynamoDB table.

Verify credentials before applying:

```shell
aws sts get-caller-identity
```

Do not put AWS access keys or secret keys in Terraform files or `backend.hcl`.

## Default Naming

No input file is required. By default, the bucket name is generated as:

```text
terraform-state-<aws-account-id>-<aws-region>
```

For example, account `123456789012` in `ap-south-1` produces `terraform-state-123456789012-ap-south-1`. Including the account ID and Region makes the default suitable for one backend bucket per account and Region while satisfying S3's global naming requirement in normal use.

Set `bucket_name` when an organization requires a specific globally unique name. Set `bucket_name_prefix` to change only the generated prefix.

## Create the Backend

From this directory:

```shell
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review the output values:

```shell
terraform output
terraform output -raw bucket_name
terraform output -raw backend_hcl_template
```

The final command prints a ready-to-edit `backend.hcl` template. Every consuming root module must replace `REPLACE_WITH_PROJECT_PATH` with its own unique state path.

### Customize the Backend

PowerShell:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Bash:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`, then run the normal `terraform plan` and `terraform apply` commands. A typical configuration is:

```hcl
aws_region         = "ap-south-1"
bucket_name_prefix = "acme-terraform-state"

tags = {
  Environment = "shared"
  Owner       = "platform-team"
}
```

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `aws_region` | `string` | `"ap-south-1"` | Region in which the backend resources are created. |
| `bucket_name` | `string` or `null` | `null` | Exact globally unique bucket name. When null, a name is generated. |
| `bucket_name_prefix` | `string` | `"terraform-state"` | Prefix for the generated bucket name. |
| `create_dynamodb_lock_table` | `bool` | `false` | Creates the deprecated DynamoDB locking table for older consumers. |
| `dynamodb_table_name` | `string` | `"terraform-state-lock"` | Name of the optional DynamoDB table. |
| `tags` | `map(string)` | `{}` | Tags merged with the module's `Name`, `ManagedBy`, and `Purpose` tags. |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_name` | S3 state bucket name. |
| `bucket_arn` | S3 state bucket ARN. |
| `aws_region` | Region containing the backend. |
| `dynamodb_table_name` | Legacy lock-table name, or `null` when disabled. |
| `backend_hcl_template` | Consumer configuration template using native S3 locking. |

## Consume the Backend

Backend initialization happens before Terraform evaluates input variables, locals, resources, data sources, or module outputs. Consequently, a backend block cannot refer directly to `var.*`, a resource, or the outputs of this bootstrap.

Add a partial backend block to the consuming root module, usually in `backend.tf` or `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {}
}
```

Create `backend.hcl` next to that consuming root module:

```hcl
bucket       = "terraform-state-123456789012-ap-south-1"
key          = "orders-service/prod/terraform.tfstate"
region       = "ap-south-1"
encrypt      = true
use_lockfile = true
```

The file contains only the attributes that would be inside `backend "s3"`; do not wrap them in a `terraform` or `backend` block.

Use a unique `key` for every independently applied Terraform root module and environment. For example:

```text
network/dev/terraform.tfstate
network/prod/terraform.tfstate
orders-service/dev/terraform.tfstate
orders-service/prod/terraform.tfstate
```

Reusing a key causes two configurations to manage the same state and can lead to destructive changes.

### Generate `backend.hcl` From Bootstrap Outputs

The following examples assume the consumer directory and `terraform-backend-state-s3` are sibling directories.

PowerShell:

```powershell
$bucket = terraform -chdir=../terraform-backend-state-s3 output -raw bucket_name
$region = terraform -chdir=../terraform-backend-state-s3 output -raw aws_region

@"
bucket       = "$bucket"
key          = "orders-service/prod/terraform.tfstate"
region       = "$region"
encrypt      = true
use_lockfile = true
"@ | Set-Content -Encoding utf8 backend.hcl
```

Bash:

```bash
bucket="$(terraform -chdir=../terraform-backend-state-s3 output -raw bucket_name)"
region="$(terraform -chdir=../terraform-backend-state-s3 output -raw aws_region)"

cat > backend.hcl <<EOF
bucket       = "$bucket"
key          = "orders-service/prod/terraform.tfstate"
region       = "$region"
encrypt      = true
use_lockfile = true
EOF
```

Change the `key` in either command to identify the consumer and environment.

### Initialize a New Consumer

Run these commands from the consuming root module:

```shell
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Terraform records the resolved backend configuration under `.terraform/`. Do not commit `.terraform/`.

### Migrate Existing Local State

First back up the current state:

PowerShell:

```powershell
terraform state pull | Set-Content -Encoding utf8 terraform-state-backup.json
```

Bash:

```bash
terraform state pull > terraform-state-backup.json
```

Then initialize the S3 backend and approve the migration prompt:

```shell
terraform init -migrate-state -backend-config=backend.hcl
terraform state list
```

Keep the backup until a subsequent `plan` confirms that the remote state is correct. State backups may contain secrets and must not be committed.

### Reconfigure an Existing Backend

When the backend settings changed but state does not need to be copied, run:

```shell
terraform init -reconfigure -backend-config=backend.hcl
```

Use `-migrate-state` instead of `-reconfigure` when changing the bucket or key and the existing state must move to the new location. Do not use both flags together.

For non-interactive automation after the backend is already configured:

```shell
terraform init -input=false -backend-config=backend.hcl
```

## Native S3 State Locking

Consumers should set:

```hcl
use_lockfile = true
```

Terraform then creates a lock object next to the state object with the `.tflock` suffix. The consumer identity needs these S3 permissions:

- `s3:ListBucket` on the state bucket.
- `s3:GetObject` and `s3:PutObject` on the state key.
- `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on the corresponding `.tflock` key.

This bootstrap secures the storage but intentionally does not create or attach IAM users and roles, because the correct principals and access boundaries are organization-specific. The TLS-deny bucket policy also does not grant access; consumer identities still require an IAM allow policy.

## Legacy DynamoDB Locking

Terraform's DynamoDB locking arguments are deprecated. Use this mode only for consumers older than Terraform 1.10.

Enable the compatibility table in the bootstrap's `terraform.tfvars`:

```hcl
create_dynamodb_lock_table = true
dynamodb_table_name        = "terraform-state-lock"
```

Apply the bootstrap again, then use the following in an older consumer's `backend.hcl`:

```hcl
bucket         = "terraform-state-123456789012-ap-south-1"
key            = "orders-service/prod/terraform.tfstate"
region         = "ap-south-1"
encrypt        = true
dynamodb_table = "terraform-state-lock"
```

Do not add `use_lockfile` to consumers whose Terraform version does not support it. When upgrading to Terraform 1.10 or later, replace `dynamodb_table` with `use_lockfile = true` and run `terraform init -reconfigure -backend-config=backend.hcl`.

## Included Consumer Example

[`examples/consumer`](examples/consumer) is a complete minimal root module. It uses the built-in `terraform_data` resource, so it demonstrates remote state without creating additional AWS infrastructure.

PowerShell:

```powershell
Set-Location examples/consumer
Copy-Item backend.hcl.example backend.hcl
# Read the real bucket with: terraform -chdir=../.. output -raw bucket_name
terraform init -backend-config=backend.hcl
terraform apply
```

Bash:

```bash
cd examples/consumer
cp backend.hcl.example backend.hcl
# Read the real bucket with: terraform -chdir=../.. output -raw bucket_name
terraform init -backend-config=backend.hcl
terraform apply
```

The bootstrap output must be read before changing into the example directory, or by using `terraform -chdir=../.. output -raw bucket_name` from the example.

## Operational Notes

- S3 versioning preserves older state object versions, but recovery is still an administrative action. Restrict access to the bucket.
- The bucket has `prevent_destroy = true` to guard against accidental destruction. Migrate every consumer state before intentionally removing the backend.
- Applying this bootstrap does not move any existing Terraform state. Migration occurs only when the consumer runs `terraform init -migrate-state`.
- `backend.hcl` is safe to commit only when it contains identifiers and non-secret settings. Supply credentials through standard AWS credential sources.
- The same S3 bucket can store many state files, provided every consuming root module uses a unique key.

## References

- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Terraform backend configuration and partial configuration](https://developer.hashicorp.com/terraform/language/backend)
- [`terraform init` command](https://developer.hashicorp.com/terraform/cli/commands/init)
