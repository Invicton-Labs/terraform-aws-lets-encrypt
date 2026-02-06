output "iam_role_arn" {
  description = "The ARN of the IAM role created for Route53 access."
  depends_on = [
    // Wait for the policy to be attached, so nothing tries to use the role before it's ready
    aws_iam_role_policy.route53_policy
  ]
  value = aws_iam_role.route53.arn
}
