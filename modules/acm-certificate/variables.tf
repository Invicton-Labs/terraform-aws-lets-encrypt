variable "region" {
  description = "The AWS region to deploy the resources in. If not provided, the provider's region will be used."
  type        = string
  default     = null
}

variable "certificate_tags" {
  description = "A map of tags to assign to the ACM certificate."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "exportable" {
  description = "Specifies whether to make the private key associated with the ACM certificate exportable."
  type        = bool
  default     = false
  nullable    = false
}

variable "acm_certificate_load_input" {
  description = "Inputs provided by the \"Invicton-Labs/terraform-aws-lets-encrypt//modules/acm-certificate-load\" module (the `inputs_for_acm_module` output value)."
  type = object({
    lambda_arn   = string
    iam_role_arn = string
  })
}
