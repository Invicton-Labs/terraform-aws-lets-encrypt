variable "region" {
  description = "The AWS region to deploy the resources in. If not provided, the provider's region will be used."
  type        = string
  default     = null
}

variable "lets_encrypt_module" {
  description = "The entire Invicton-Labs/terraform-aws-lets-encrypt module object."
  type = object({
    lambda_module = object({
      lambda = object({
        arn = string
      })
    })
  })
  nullable = false
}

variable "key_type" {
  description = "The type of private key to generate for the certificate. Can be 'ec' or 'rsa'."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.key_type == null ? true : contains(["ec", "rsa"], var.key_type)
    error_message = "The `key_type` variable must be \"ec\" or \"rsa\"."
  }
}

variable "key_size" {
  description = "The size of the private key to generate for the certificate. For 'ec', can be 256 or 384. For 'rsa', can be 2048, 3072, or 4096."
  type        = number
  default     = null
  nullable    = true
  validation {
    condition = (
      var.key_size == null ? true : (
        var.key_type == null ? false : (
          (var.key_type == "ec" && contains([256, 384], var.key_size)) ||
          (var.key_type == "rsa" && contains([2048, 3072, 4096], var.key_size))
        )
      )
    )
    error_message = "The `key_size` variable must be 256 or 384 for 'ec' keys, and 2048, 3072, or 4096 for 'rsa' keys. If no `key_type` was provided, no `key_size` can be provided."
  }
}

variable "domains" {
  description = "A list of domains to request the certificate for. The first domain in the list will be used as the Common Name (CN) in the certificate, and all domains will be included as Subject Alternative Names (SANs)."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.domains) > 0
    error_message = "At least one domain must be provided in the `domains` input variable."
  }
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

variable "lambda_python_version" {
  description = "The Python version to use for the Lambda runtime. Provided for long-term compatibility if the default is deprecated."
  type        = string
  default     = "3.14"
  nullable    = false
}

variable "cloudwatch_log_retention_days" {
  description = "The number of days to retain CloudWatch logs for the Lambda function. If not provided, logs will be kept indefinitely."
  type        = number
  default     = null
  nullable    = true
}

variable "lambda_tags" {
  description = "A map of tags to assign to the Lambda function that generates the certificate."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "renewal_triggers" {
  description = "A value that, when changed in any way, forces a new certificate to be generated. Note that changes to the `domains` variable also force a new certificate."
  type        = any
  default     = {}
  nullable    = false
}

variable "add_random_subdomain" {
  description = "Whether to add a random subdomain to the certificate request to circumvent the 'exact set of identifiers' limit in Let's Encrypt. Useful when multiple certificates with overlapping domains are being requested."
  type        = bool
  default     = false
  nullable    = false
}

variable "acm_certificate_modules" {
  description = "A list of all \"Invicton-Labs/terraform-aws-lets-encrypt//modules/acm-certificate\" modules to load the generated certificate into."
  type = list(object({
    certificate_arn  = string
    iam_role_arn     = string
    certificate_uuid = string
    certificate_tags = map(string)
  }))

  validation {
    condition     = length(var.acm_certificate_modules) > 0
    error_message = "At least one ACM certificate module must be provided in the `acm_certificate_modules` variable."
  }

  validation {
    condition = length([
      for value in var.acm_certificate_modules :
      value.certificate_uuid
      ]) == length(distinct([
        for value in var.acm_certificate_modules :
        value.certificate_uuid
    ]))
    error_message = "The same \"Invicton-Labs/terraform-aws-lets-encrypt//modules/acm-certificate\" module has been provided more than once. Each module passed in the `acm_certificate_modules` variable must be unique."
  }
}

variable "s3_destinations" {
  description = "Parameters for any S3 destinations where the certificate and/or key should be stored."
  type = list(object({
    // The ID of the bucket to store the certificate/key in
    bucket_id = string
    // Whether to store the certificate in S3
    store_certificate = bool
    // Whether to store the private key in S3
    store_private_key = bool
    // The prefix to append to the S3 object key for the certificate and private key
    object_key_prefix = optional(string, "")
    // The object key to use for the certificate in S3 (only if `store_certificate` is true).
    // This gets appended to the key prefix.
    certificate_object_key = optional(string, "certificate.pem")
    // The object key to use for the intermediate certificates in S3 (only if `store_certificate` is true).
    // This gets appended to the key prefix.
    intermediate_certificates_object_key = optional(string, "intermediate-certificates.pem")
    // The object key to use for the intermediate certificates in S3 (only if `store_certificate` is true).
    // This gets appended to the key prefix.
    certificate_chain_object_key = optional(string, "certificate-chain.pem")
    // The object key to use for the private key in S3 (only if `store_private_key` is true)
    // This gets appended to the key prefix.
    private_key_object_key = optional(string, "key.pem")
    // The IAM role ARN to use when writing to S3. Must be assumable by the Lambda's execution role. If not provided, the Lambda's execution role will be used.
    iam_role_arn = optional(string, null)
  }))
  default  = []
  nullable = false
  validation {
    condition = length([
      for s3_dest in var.s3_destinations :
      null
      if s3_dest.store_certificate || s3_dest.store_private_key
    ]) == length(var.s3_destinations)
    error_message = "All S3 destinations must have at least one of `store_certificate` or `store_private_key` set to `true`."
  }
}
