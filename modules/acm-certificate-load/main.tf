data "aws_region" "current" {}
data "aws_caller_identity" "this" {}

locals {
  region = var.region != null ? var.region : data.aws_region.current.region

  acm_arns_to_iam_roles = {
    for value in var.acm_certificate_modules :
    (value.certificate_arn) => value.iam_role_arn
  }

  acm_arns_to_tags = {
    for value in var.acm_certificate_modules :
    (value.certificate_arn) => value.certificate_tags
  }
}
