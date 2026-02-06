
// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "route53_core" {
  statement {
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      // Grant it permission on each hosted zone ID provided, but only if no specific role ARN is provided for that zone
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
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
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      "arn:aws:route53:::hostedzone/${id}"
    ]
  }
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "route53" {
  source_policy_documents = [
    data.aws_iam_policy_document.route53_core.json
  ]

  // Allow assuming the IAM roles
  dynamic "statement" {
    for_each = length([
      for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
      role_arn
      if role_arn != null
    ]) > 0 ? [null] : []
    content {
      actions = [
        "sts:AssumeRole",
      ]
      resources = [
        for id, role_arn in var.hosted_zone_ids_to_iam_role_arns :
        role_arn
        if role_arn != null
      ]
    }
  }
}
