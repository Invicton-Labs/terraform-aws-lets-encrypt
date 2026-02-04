data "aws_region" "current" {}

locals {
  region = var.region != null ? var.region : data.aws_region.current.region
  // Must match that specified in the acm-certificate-load submodule
  version_tag_key = "LetsEncryptCertificateVersion"
}

resource "random_uuid" "acm" {}
