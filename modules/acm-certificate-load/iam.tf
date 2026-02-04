// The policy for the Lambda to use for generating certificates and loading them into ACM
data "aws_iam_policy_document" "acm" {

  // Allow invoking the Let's Encrypt Lambda function
  statement {
    sid = "AllowInvokingLetsEncryptLambda"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [
      var.lets_encrypt_module.lambda_module.lambda.arn
    ]
  }

  // Allow assuming the IAM roles that allow loading into ACM
  dynamic "statement" {
    for_each = length(var.acm_certificate_modules) > 0 ? [null] : []
    content {
      sid = "AllowAssumingAcmIamRoles"
      actions = [
        "sts:AssumeRole"
      ]
      resources = [
        for acm_module in var.acm_certificate_modules :
        acm_module.iam_role_arn
      ]
    }
  }

  // Allow assuming the IAM roles that allow storing in S3.
  // Only include this statement if any S3 destinations with IAM roles are provided.
  dynamic "statement" {
    for_each = length([
      for s3_dest in var.s3_destinations :
      null
      if s3_dest.iam_role_arn != null
    ]) > 0 ? [null] : []
    content {
      sid = "AllowAssumingS3IamRoles"
      actions = [
        "sts:AssumeRole"
      ]
      resources = [
        for s3_destination in var.s3_destinations :
        s3_destination.iam_role_arn
        if s3_destination.iam_role_arn != null
      ]
    }
  }

  // For any S3 destinations that don't have an IAM role specified, allow the Lambda to write to S3 directly
  dynamic "statement" {
    for_each = length([
      for s3_dest in var.s3_destinations :
      null
      if s3_dest.iam_role_arn == null
    ]) > 0 ? [null] : []
    content {
      sid = "AllowWritingToS3"
      actions = [
        "s3:PutObject",
        "s3:PutObjectTagging",
      ]
      // Restrict permissions to the specific keys
      resources = flatten([
        for s3_destination in var.s3_destinations :
        [
          s3_destination.store_certificate ? [
            "arn:aws:s3:::${s3_destination.bucket_id}/${s3_destination.object_key_prefix}${s3_destination.certificate_object_key}",
            "arn:aws:s3:::${s3_destination.bucket_id}/${s3_destination.object_key_prefix}${s3_destination.intermediate_certificates_object_key}",
            "arn:aws:s3:::${s3_destination.bucket_id}/${s3_destination.object_key_prefix}${s3_destination.certificate_chain_object_key}",
          ] : [],
          s3_destination.store_certificate ? [
            "arn:aws:s3:::${s3_destination.bucket_id}/${s3_destination.object_key_prefix}${s3_destination.private_key_object_key}"
          ] : [],
        ]
        if s3_destination.iam_role_arn == null
      ])
    }
  }
}
