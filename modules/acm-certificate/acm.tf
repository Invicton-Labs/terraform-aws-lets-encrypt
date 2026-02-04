
// We need to generate a dummy self-signed key and cert to create
// the ACM certificate. We need to create the certificate before running
// the Lambda so we know the ARN and can set permissions appropriately.
// You may ask "why don't we just get the actual key/cert with a lambda invokation
// use it when creating the cert?". Well, because then your private key is in
// the state file...
resource "tls_private_key" "dummy" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}
resource "tls_self_signed_cert" "dummy" {
  private_key_pem = tls_private_key.dummy.private_key_pem
  subject {
    // This doesn't matter, it's just a placeholder for the ACM cert
    // to be created so we know the ARN in advance.
    common_name  = "example.com"
    organization = "ACME Examples, Inc"
  }
  // Set it to 1000 years so it doesn't try to re-create itself
  validity_period_hours = 24 * 365 * 100
  allowed_uses = [
    // Use these initially, since all LetsEncrypt certs include it. This
    // allows us to re-import the certificate, since you can only re-import
    // if the new cert has all of the uses of the existing cert (plus any new ones).

    // Need one Key Usage
    "digital_signature",

    // And one Extended Key Usage
    "server_auth",
  ]
}

// Get all default tags on the provider
data "aws_default_tags" "this" {}

locals {
  all_cert_tags = merge(data.aws_default_tags.this.tags, var.certificate_tags)
}

resource "terraform_data" "exportable" {
  input = var.exportable
}

resource "aws_acm_certificate" "this" {
  region           = local.region
  private_key      = tls_private_key.dummy.private_key_pem
  certificate_body = tls_self_signed_cert.dummy.cert_pem
  options {
    export = var.exportable ? "ENABLED" : "DISABLED"
  }
  // The var.certificate_tags will be set by the Lambda, but set it here as well
  // in case there are SCPs preventing creating resources without specific tags.
  tags = merge(local.all_cert_tags, {
    // Must set an initial version
    (local.version_tag_key) = "unset"
  })
  lifecycle {
    ignore_changes = [
      region,
      private_key,
      certificate_body,
      certificate_chain,
      tags,
      // There's a bug in the provider. It won't let you set this value to "ENABLED" when you import a certificate,
      // but if you set it to "DISABLED" then it shows a perpetual diff trying to change it to "ENABLED".
      options[0].certificate_transparency_logging_preference
    ]
    replace_triggered_by = [
      // We can't update options for imported certificates, so we have 
      // to create a new one if this perameter changes.
      terraform_data.exportable
    ]
  }
}
