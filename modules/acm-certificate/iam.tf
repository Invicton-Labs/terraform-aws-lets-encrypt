data "aws_arn" "load_lambda" {
  arn = var.acm_certificate_load_input.lambda_arn
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "assume_role" {
  statement {
    sid = "AllowLambdaToAssume"
    actions = [
      "sts:AssumeRole",
    ]
    // Allow the account where the Lambda is deployed to assume this role
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${data.aws_arn.load_lambda.account}:root"
      ]
    }
    // Restrict it to only be assumed by the specific Lambda role
    condition {
      test     = "ArnEquals"
      variable = "aws:PrincipalArn"
      values = [
        var.acm_certificate_load_input.iam_role_arn,
      ]
    }
  }
}

// Design a policy that grants the necessary permissions to write the Route53 records
data "aws_iam_policy_document" "acm" {
  statement {
    sid = "AllowReimport"
    actions = [
      "acm:ImportCertificate",
    ]
    resources = [
      aws_acm_certificate.this.arn
    ]
  }

  // Allow adding tags
  statement {
    sid = "AllowAddingTags"
    actions = [
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate"
    ]
    resources = [
      aws_acm_certificate.this.arn
    ]
  }

  // Allow removing tags from the certificate
  statement {
    sid = "AllowRemovingTags"
    actions = [
      "acm:RemoveTagsFromCertificate"
    ]
    resources = [
      aws_acm_certificate.this.arn
    ]
    // Ensure that the version tag isn't being removed
    condition {
      test     = "ForAllValues:StringNotEquals"
      variable = "aws:TagKeys"
      values = [
        local.version_tag_key
      ]
    }
  }
}

resource "aws_iam_role" "acm_role" {
  name_prefix           = "lets-encrypt-acm-${local.region}-"
  path                  = "/lets-encrypt/"
  force_detach_policies = true
  assume_role_policy    = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_role_policy" "acm_policy" {
  name   = "acm-certificate-management"
  role   = aws_iam_role.acm_role.name
  policy = data.aws_iam_policy_document.acm.json
}
