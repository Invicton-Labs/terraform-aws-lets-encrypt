output "certificate_arn" {
  description = "The ARN of the certificate managed by this module."
  value       = aws_acm_certificate.this.arn
}

output "iam_role_arn" {
  description = "The ARN of the role that allows updating the ACM certificate."
  value       = aws_iam_role.acm_role.arn
}

output "certificate_uuid" {
  description = "A unique ID for the certificate managed by this module."
  value       = random_uuid.acm.result
}

output "certificate_tags" {
  description = "The tags assigned to the ACM certificate."
  value       = local.all_cert_tags
}

output "region" {
  description = "The AWS region where the ACM certificate is deployed."
  value       = local.region
}
