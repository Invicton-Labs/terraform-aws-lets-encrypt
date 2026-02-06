variable "region" {
  description = "The AWS region to deploy the resources in. If not provided, the provider's region will be used."
  type        = string
  default     = null
}

variable "function_name" {
  description = "The name to assign to the Lambda function. If not provided, a unique name will be generated."
  type        = string
  default     = null
}

variable "architecture" {
  description = "The architecture for the Lambda function."
  type        = string
  default     = "arm64"
  nullable    = false
  validation {
    condition     = contains(["arm64", "x86_64"], var.architecture)
    error_message = "The `architecture` variable must be \"arm64\" or \"x86_64"
  }
}

variable "vpc_config" {
  description = "Configuration block for the VPC settings of the Lambda function."
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default  = null
  nullable = true
}

variable "hosted_zone_ids_to_iam_role_arns" {
  description = "A mapping of Route53 hosted zone IDs that contain the domains the Lambda function should be able to create certificates for, to IAM role ARNs for a role that has permissions to modify records in that zone. If the role ARN is null, the Lambda's role will be used."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "lambda_python_version" {
  description = "The Python version to use for the Lambda runtime. Provided for long-term compatibility if the default is deprecated."
  type        = string
  default     = "3.14"
  nullable    = false
}

variable "permitted_domains" {
  description = "A list of domains that the Lambda should have permissions to get certificates for. Only applies for domains where no dedicated IAM role ARN is provided. If not provided, any domain that falls within any of the permitted hosted zones will be allowed. Note that '*' and '?' have special meanings as they do in IAM policies; using \"*.example.com\" will allow the Lambda to get certificates for \"foo.example.com\", \"bar.example.com\", etc. Actual wildcard domains are always permitted, as Let's Encrypt does not consider that to be a separate validation from the parent domain."
  type        = list(string)
  default     = null
  nullable    = true
}

variable "cloudwatch_log_retention_days" {
  description = "The number of days to retain CloudWatch logs for the Lambda function. If not provided, logs will be kept indefinitely."
  type        = number
  default     = null
  nullable    = true
}

variable "dns_propagation_delay_seconds" {
  description = "The number of seconds to wait after creating DNS validation records before proceeding with certificate validation. This can help ensure that the DNS changes have propagated. Defaults to 10 seconds."
  type        = number
  default     = 10
  nullable    = false
}

variable "default_key_type" {
  description = "The default type of private key to generate for the certificate. Can be 'ec' or 'rsa'."
  type        = string
  default     = "ec"
  nullable    = false
  validation {
    condition     = contains(["ec", "rsa"], var.default_key_type)
    error_message = "The `default_key_type` variable must be \"ec\" or \"rsa\"."
  }
}
variable "default_key_size" {
  description = "The default size of the private key to generate for the certificate. For 'ec', can be 256 or 384. For 'rsa', can be 2048, 3072, or 4096."
  type        = number
  default     = 384
  nullable    = false
  validation {
    condition = (
      (var.default_key_type == "ec" && contains([256, 384], var.default_key_size)) ||
      (var.default_key_type == "rsa" && contains([2048, 3072, 4096], var.default_key_size))
    )
    error_message = "The `default_key_size` variable must be 256 or 384 for 'ec' keys, and 2048, 3072, or 4096 for 'rsa' keys."
  }
}
