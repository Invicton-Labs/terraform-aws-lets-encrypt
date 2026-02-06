output "route53_policy" {
  description = "The IAM policy document (JSON) that is needed to allow Route53 access for domain validation. This policy must be attached to the IAM role passed in the `route53_iam_role_arn` variable, if provided."
  value       = data.aws_iam_policy_document.route53.json
}

output "lambda_module" {
  description = "The entire Invicton-Labs/terraform-aws-lambda-set module, so various parameters can be accessed outside this module."
  value       = module.lambda_certbot
}
