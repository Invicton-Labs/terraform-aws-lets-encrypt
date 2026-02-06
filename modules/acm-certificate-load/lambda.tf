module "function_name_provided" {
  source  = "Invicton-Labs/input-provided/null"
  version = "~>0.2.0"
  input   = var.function_name
}

resource "random_id" "lambda" {
  byte_length = 16
}

locals {
  function_name = module.function_name_provided.provided ? var.function_name : "lets-encrypt-acm-${random_id.lambda.hex}"
  runtime       = "python${var.lambda_python_version}"
  // This is the domain prefix that ACME uses for DNS validation
  record_prefix   = "_acme-challenge"
  version_tag_key = "LetsEncryptCertificateVersion"
}

module "lambda_acm" {
  source        = "Invicton-Labs/lambda-set/aws"
  version       = "~>0.8.1"
  region        = local.region
  edge          = false
  function_name = local.function_name
  lambda_config = {
    description   = "Generates certificates using Let's Encrypt"
    handler       = "main.lambda_handler"
    runtime       = local.runtime
    architectures = [var.architecture]
    memory_size   = 256
    timeout       = 600
    publish       = false
    vpc_config    = var.vpc_config
    environment = {
      variables = {
        LETS_ENCRYPT_LAMBDA_ARN     = var.lets_encrypt_module.lambda_module.lambda.arn
        CERTIFICATE_VERSION_TAG_KEY = local.version_tag_key
      }
    }
    tags = var.lambda_tags
  }
  role_policies = [
    data.aws_iam_policy_document.acm.json
  ]
  source_directory               = "${path.module}/lambda"
  archive_output_directory       = "${path.module}/archives/"
  cloudwatch_logs_retention_days = var.cloudwatch_log_retention_days
}
