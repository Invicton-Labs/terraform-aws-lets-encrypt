output "region" {
  description = "The AWS region where the Lambda is deployed."
  value       = local.region
}

output "lambda_role_arn" {
  description = "The ARN of the role that the Lambda assumes."
  value       = module.lambda_acm.iam_role_arn
}

output "inputs_for_acm_module" {
  description = "Inputs that must be passed to the \"Invicton-Labs/terraform-aws-lets-encrypt//modules/acm-certificate\" module."
  value = {
    // Use the predetermined function ARN that's available before the Lambda is created.
    // This allows it to be used in policies that need to be created before the Lambda is.
    lambda_arn   = module.lambda_acm.predetermined_lambda_arn
    iam_role_arn = module.lambda_acm.iam_role_arn
  }
}

output "complete" {
  description = "A value that is not available until the certificate loading is complete. Use this in `depends_on` for things that must wait until the real certificate is loaded."
  value       = true // TODO: aws_lambda_invocation.load_certificate.result == null ? false : true
}
