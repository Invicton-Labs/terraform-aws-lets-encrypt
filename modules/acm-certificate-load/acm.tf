locals {
  domains = sort(distinct(var.domains))

  // Calculate a version hash based on the renewal triggers, domains, key type/size, and certificate ARNs.
  // If any of these things change, the certificate needs to be regenerated.
  version = base64sha256(jsonencode(
    {
      input_triggers       = var.renewal_triggers
      domains              = local.domains
      key_type             = var.key_type
      key_size             = var.key_size
      certificate_arns     = sort(keys(local.acm_arns_to_iam_roles))
      add_random_subdomain = var.add_random_subdomain
      s3_destinations      = var.s3_destinations
    }
  ))
}

// Run the Lambda function that imports the LetsEncrypt certificate into ACM
resource "aws_lambda_invocation" "load_certificate" {
  region        = local.region
  function_name = module.lambda_acm.lambda.arn
  input = jsonencode({
    domains = var.domains
    // Always include the provider's default tags as well
    acm_arns_to_tags = local.acm_arns_to_tags
    key_type         = var.key_type
    key_size         = var.key_size
    // These are the defaults for LetsEncrypt
    key_usages = [
      "digitalSignature",
      "serverAuth",
    ]
    acm_arns_to_iam_roles = local.acm_arns_to_iam_roles
    add_random_subdomain  = var.add_random_subdomain
    s3_destinations       = var.s3_destinations
    // The version is a hash of the renewal triggers the provided domains, and the certificate ARN.
    // When this changes, it forces a new certificate to be generated and imported (will retain the same ARN).
    version = local.version
  })
}
