data "aws_region" "current" {}

locals {
  region        = var.region != null ? var.region : data.aws_region.current.region
  record_prefix = "_acme-challenge"
}
