module "function_name_provided" {
  source  = "Invicton-Labs/input-provided/null"
  version = "~>0.2.0"
  input   = var.function_name
}

resource "random_id" "lambda" {
  count       = module.function_name_provided.provided ? 0 : 1
  byte_length = 16
}

locals {
  function_name = module.function_name_provided.provided ? var.function_name : "lets-encrypt-${random_id.lambda[0].hex}"
  runtime       = "python${var.lambda_python_version}"
  record_prefix = "_acme-challenge"
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "route53_core" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      // Grant it permission on each hosted zone ID provided, but only if no specific role ARN is provided for that zone
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      "arn:aws:route53:::hostedzone/${id}"
    ]
    // Restrict it to records starting with "_acme-challenge.", which Let's Encrypt uses for validation
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values = var.permitted_domains != null ? [
        for domain in var.permitted_domains :
        "${local.record_prefix}.${domain}"
        ] : [
        "${local.record_prefix}.*"
      ]
    }
    // Restrict it to TXT records only
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values = [
        "TXT"
      ]
    }
  }
  // Allow reading hosted zone info
  statement {
    actions = [
      "route53:GetHostedZone",
    ]
    resources = [
      // Grant it permission on each hosted zone ID provided, but only if no specific role ARN is provided for that zone
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      "arn:aws:route53:::hostedzone/${id}"
    ]
  }

  // Allow assuming the IAM roles
  statement {
    actions = [
      "sts:AssumeRole",
    ]
    resources = [
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      role_arn
      if role_arn != null
    ]
  }
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "route53" {
  source_policy_documents = [
    data.aws_iam_policy_document.route53_core.json
  ]

  // Allow assuming the IAM roles
  statement {
    actions = [
      "sts:AssumeRole",
    ]
    resources = [
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      role_arn
      if role_arn != null
    ]
  }
}

// Get the Certbot layer
module "layer_certbot" {
  source          = "Invicton-Labs/public-lambda-layer/aws"
  version         = "~>0.1.0"
  package         = "certbot"
  package_version = "5.2.2"
  runtime         = local.runtime
  architecture    = var.architecture
  region          = local.region
}

// Get the Cryptography layer
module "layer_cryptography" {
  source          = "Invicton-Labs/public-lambda-layer/aws"
  version         = "~>0.1.0"
  package         = "cryptography"
  package_version = "46.0.3"
  runtime         = local.runtime
  architecture    = var.architecture
  region          = local.region
}

module "lambda_certbot" {
  source        = "Invicton-Labs/lambda-set/aws"
  version       = "~>0.8.0"
  region        = local.region
  edge          = false
  function_name = local.function_name
  lambda_config = {
    description   = "Generates certificates using Let's Encrypt"
    handler       = "main.lambda_handler"
    runtime       = local.runtime
    architectures = [var.architecture]
    memory_size   = 256
    timeout       = 300
    publish       = false
    vpc_config    = var.vpc_config
    environment = {
      variables = {
        HOSTED_ZONE_IDS_TO_IAM_ROLE_ARNS = jsonencode(var.hosted_zone_ids_to_iam_role_arns)
        ROUTE53_POLICY                   = data.aws_iam_policy_document.route53_core.json
        RECORD_PREFIX                    = local.record_prefix
        DNS_PROPAGATION_DELAY_SECONDS    = var.dns_propagation_delay_seconds
        DEFAULT_KEY_TYPE                 = var.default_key_type
        DEFAULT_KEY_SIZE                 = var.default_key_size
      }
    }
    layers = [
      module.layer_certbot.arn,
      module.layer_cryptography.arn
    ]
  }
  role_policies = flatten([
    // If it's in a separate account, we assume a different role with the permissions, so we don't need the permissions here
    data.aws_iam_policy_document.route53.json,
    [
      for policy in data.aws_iam_policy_document.assume_route53 :
      policy.json
    ]
  ])
  source_directory               = "${path.module}/lambda"
  archive_output_directory       = "${path.module}/archives/"
  cloudwatch_logs_retention_days = var.cloudwatch_log_retention_days
}

# Complete event invoke configuration
resource "aws_lambda_function_event_invoke_config" "lambda" {
  region        = local.region
  function_name = module.lambda_certbot.lambda.function_name
  # Prohibit retries, we don't want them on certificate generation failures
  maximum_retry_attempts = 0
}
