variable "route53_zone_ids" {
  description = "A list of all Route53 zone IDs that this role should be permitted to modify."
  type        = list(string)
  nullable    = false
}

variable "assume_role_aws_principal_identifiers" {
  description = "A list of AWS IAM principals (ARNs) that should be allowed to assume the Route53 role."
  type        = list(string)
  nullable    = false
}
