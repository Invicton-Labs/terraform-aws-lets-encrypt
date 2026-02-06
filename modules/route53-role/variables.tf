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

variable "permitted_domains" {
  description = "A list of domains that the role should have permissions to get certificates for. If not provided, any domain that falls within any of the permitted hosted zones will be allowed. Note that '*' and '?' have special meanings as they do in IAM policies; using \"*.example.com\" will allow the Lambda to get certificates for \"foo.example.com\", \"bar.example.com\", etc. Actual wildcard domains are always permitted, as Let's Encrypt does not consider that to be a separate validation from the parent domain."
  type        = list(string)
  default     = null
  nullable    = true
}
