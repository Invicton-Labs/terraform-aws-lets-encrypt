// A policy that allows the P3 prod account to assume the role
data "aws_iam_policy_document" "assume" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    principals {
      type        = "AWS"
      identifiers = var.assume_role_aws_principal_identifiers
    }
  }
}

// A role that is able to update Route53 (might be in a different account)
resource "aws_iam_role" "route53" {
  name_prefix        = "letsencrypt-route53-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "route53" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      // Grant it permission on each hosted zone ID provided, but only if no specific role ARN is provided for that zone
      for id in var.route53_zone_ids :
      "arn:aws:route53:::hostedzone/${id}"
    ]
    // Restrict it to records starting with "_acme-challenge.", which Let's Encrypt uses for validation
    condition {
      test     = "ForAllValues:StringLike"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values = var.permitted_domains != null ? [
        for domain in var.permitted_domains :
        "${local.record_prefix}.${domain}"
        ] : [
        "${local.record_prefix}.*"
      ]
    }
    // Restrict it to TXT records only
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values = [
        "TXT"
      ]
    }
  }
  // Allow reading hosted zone info
  statement {
    actions = [
      "route53:GetHostedZone",
    ]
    resources = [
      // Grant it permission on each hosted zone ID provided, but only if no specific role ARN is provided for that zone
      for id in var.route53_zone_ids :
      "arn:aws:route53:::hostedzone/${id}"
    ]
  }
}

resource "aws_iam_role_policy" "route53_policy" {
  name   = "route53-access"
  role   = aws_iam_role.route53.name
  policy = data.aws_iam_policy_document.route53.json
}
