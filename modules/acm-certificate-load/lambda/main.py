import logging
import json
import os
import boto3
from botocore.config import Config

log = logging.getLogger()
log.setLevel(logging.INFO)

lambda_arn = os.environ["LETS_ENCRYPT_LAMBDA_ARN"]
version_tag_key = os.environ["CERTIFICATE_VERSION_TAG_KEY"]

lambda_client = boto3.client(
    "lambda",
    config=Config(
        # Overwrite the config to allow for long-running invocations
        read_timeout=900,
        connect_timeout=30,
        # Never retry
        retries={"total_max_attempts": 1, "mode": "standard"},
    ),
)
s3_client = boto3.client("s3")
sts_client = boto3.client("sts")


def get_acm_client(iam_role_arn, certificate_arn):
    # Assume the role to access the ACM certificate
    temp_credentials = sts_client.assume_role(
        RoleArn=iam_role_arn, RoleSessionName="ACMCertificateLoadSession"
    )["Credentials"]

    # Extract the region from the certificate ARN
    region = certificate_arn.split(":")[3]

    # Start a session with that role's temporary credentials
    session = boto3.Session(
        aws_access_key_id=temp_credentials["AccessKeyId"],
        aws_secret_access_key=temp_credentials["SecretAccessKey"],
        aws_session_token=temp_credentials["SessionToken"],
    )

    # Create a client that uses that session, and create it in the certificate's region
    return session.client("acm", region_name=region)


def get_s3_client(iam_role_arn):
    # Assume the role to access the ACM certificate
    temp_credentials = sts_client.assume_role(
        RoleArn=iam_role_arn, RoleSessionName="S3CertificateStoreSession"
    )["Credentials"]

    # Start a session with that role's temporary credentials
    session = boto3.Session(
        aws_access_key_id=temp_credentials["AccessKeyId"],
        aws_secret_access_key=temp_credentials["SecretAccessKey"],
        aws_session_token=temp_credentials["SessionToken"],
    )

    # Create a client that uses that session, and create it in the certificate's region
    return session.client("s3")


# TODO: support tagging the S3 objects
def store_cert_in_s3_destination(
    s3_destination, cert_pem, intermediate_certs_pem, key_pem
):
    if s3_destination["iam_role_arn"] is not None:
        tmp_s3_client = get_s3_client(s3_destination["iam_role_arn"])
    else:
        tmp_s3_client = s3_client

    if s3_destination["store_certificate"]:
        cert_key = (
            s3_destination["object_key_prefix"]
            + s3_destination["certificate_object_key"]
        )
        log.info(
            "Storing certificate in S3: bucket=%s, key=%s",
            s3_destination["bucket_id"],
            cert_key,
        )
        tmp_s3_client.put_object(
            Bucket=s3_destination["bucket_id"],
            Key=cert_key,
            Body=cert_pem.encode("utf-8"),
        )
        intermediate_key = (
            s3_destination["object_key_prefix"]
            + s3_destination["intermediate_certificates_object_key"]
        )
        log.info(
            "Storing intermediate certificates in S3: bucket=%s, key=%s",
            s3_destination["bucket_id"],
            intermediate_key,
        )
        tmp_s3_client.put_object(
            Bucket=s3_destination["bucket_id"],
            Key=intermediate_key,
            Body=intermediate_certs_pem.encode("utf-8"),
        )
        chain_key = (
            s3_destination["object_key_prefix"]
            + s3_destination["certificate_chain_object_key"]
        )
        log.info(
            "Storing certificate chain in S3: bucket=%s, key=%s",
            s3_destination["bucket_id"],
            chain_key,
        )
        tmp_s3_client.put_object(
            Bucket=s3_destination["bucket_id"],
            Key=chain_key,
            Body=(cert_pem + intermediate_certs_pem).encode("utf-8"),
        )

    if s3_destination["store_private_key"]:
        pk_key = (
            s3_destination["object_key_prefix"]
            + s3_destination["private_key_object_key"]
        )
        log.info(
            "Storing private key in S3: bucket=%s, key=%s",
            s3_destination["bucket_id"],
            pk_key,
        )
        tmp_s3_client.put_object(
            Bucket=s3_destination["bucket_id"],
            Key=pk_key,
            Body=key_pem.encode("utf-8"),
        )


def lambda_handler(event, context):
    log.info("Event: %s", json.dumps(event))
    request_id = context.aws_request_id
    log.info("Request ID: %s", request_id)
    # Ensure a version was provided
    if "version" not in event:
        raise ValueError("Version must be provided")

    version = event["version"]
    key_type = event["key_type"]
    key_size = event["key_size"]
    key_usages = event["key_usages"]
    acm_arns_to_iam_roles = event["acm_arns_to_iam_roles"]
    acm_arns_to_tags = event["acm_arns_to_tags"]
    add_random_subdomain = event["add_random_subdomain"]
    s3_destinations = event["s3_destinations"]

    first_certificate_arn = list(acm_arns_to_iam_roles.keys())[0]
    first_certificate_client = get_acm_client(
        acm_arns_to_iam_roles[first_certificate_arn], first_certificate_arn
    )
    existing_tags = {
        tag["Key"]: tag["Value"]
        for tag in first_certificate_client.list_tags_for_certificate(
            # Get the version tag from the first ACM cert in the list. If the cert ARNs have changed, then
            # the new version will be different and will force a re-generation, so it's OK to just use the first one.
            CertificateArn=first_certificate_arn
        )["Tags"]
    }

    existing_version = existing_tags.get(version_tag_key, None)
    if existing_version is None:
        raise AssertionError(
            f"No version tag ({version_tag_key}) found on existing certificate {first_certificate_arn}"
        )

    reimport_required = False
    reimport_args = None

    # If the version has changed, generate a new cert
    if version != existing_version:
        log.info(
            "First deployment or version has changed, generating new certificate..."
        )
        reimport_required = True

        response = lambda_client.invoke(
            FunctionName=lambda_arn,
            InvocationType="RequestResponse",
            Payload=json.dumps(
                {
                    "add_random_subdomain": add_random_subdomain,
                    "key_type": key_type,
                    "key_size": key_size,
                    "key_usages": key_usages,
                    "domains": event["domains"],
                    "source_request_id": request_id,
                }
            ),
        )

        payload = json.loads(response["Payload"].read())

        if "errorMessage" in payload:
            log.warning("Payload:\n%s", payload)
            raise AssertionError(f"Certbot Lambda error: {payload['errorMessage']}")

        reimport_args = {
            "Certificate": payload["cert_pem"].encode("utf-8"),
            "PrivateKey": payload["key_pem"].encode("utf-8"),
            "CertificateChain": payload["intermediate_chain_pem"].encode("utf-8"),
        }

        # Store in S3 destinations
        for s3_destination in s3_destinations:
            store_cert_in_s3_destination(
                s3_destination,
                payload["cert_pem"],
                payload["intermediate_chain_pem"],
                payload["key_pem"],
            )

    else:
        log.info("Version has not changed, no new certificate necessary")

    for certificate_arn, iam_role_arn in acm_arns_to_iam_roles.items():
        log.info(
            "Processing certificate ARN %s with IAM role %s",
            certificate_arn,
            iam_role_arn,
        )

        # Get the tags for this certificate
        certificate_tags = acm_arns_to_tags[certificate_arn]
        # Always ensure the version tag is set
        certificate_tags[version_tag_key] = version

        # Create a client that uses that session, and create it in the certificate's region
        tmp_acm_client = get_acm_client(iam_role_arn, certificate_arn)

        if reimport_required:
            # We have to reimport the content
            log.info(
                "Re-importing certificate into ACM with CertificateArn: %s\nTags:%s",
                certificate_arn,
                json.dumps(reimport_args.get("Tags", [])),
            )
            tmp_acm_client.import_certificate(
                CertificateArn=certificate_arn,
                Certificate=payload["cert_pem"].encode("utf-8"),
                PrivateKey=payload["key_pem"].encode("utf-8"),
                CertificateChain=payload["intermediate_chain_pem"].encode("utf-8"),
            )
        else:
            log.info("No re-import necessary for CertificateArn: %s", certificate_arn)

        # Get the existing tags for this cert
        existing_tags = {
            tag["Key"]: tag["Value"]
            for tag in tmp_acm_client.list_tags_for_certificate(
                # Get the version tag from the first ACM cert in the list. If the cert ARNs have changed, then
                # the new version will be different and will force a re-generation, so it's OK to just use the first one.
                CertificateArn=certificate_arn
            )["Tags"]
        }

        # Check if there are any that need to be removed
        tags_to_remove = {
            key: value
            for key, value in existing_tags.items()
            # Remove the tag if it's not the ID tag, and if the key doesn't exist in the new tags OR the value has changed
            if key not in certificate_tags
        }

        if len(tags_to_remove) > 0:
            log.info("Removing tags: %s", json.dumps(tags_to_remove))
            tmp_acm_client.remove_tags_from_certificate(
                CertificateArn=certificate_arn,
                Tags=[
                    {
                        "Key": key,
                        "Value": value,
                    }
                    for key, value in tags_to_remove.items()
                ],
            )

        # New tags to add
        tags_to_add = {
            key: value
            for key, value in certificate_tags.items()
            # Add the tag if it doesn't exist yet or if the value has changed
            if key not in existing_tags
            or existing_tags[key] != value
            or key in tags_to_remove
        }

        # Add any new/changed tags
        if len(tags_to_add) > 0:
            log.info("Adding tags: %s", json.dumps(tags_to_add))
            tmp_acm_client.add_tags_to_certificate(
                CertificateArn=certificate_arn,
                Tags=[
                    {
                        "Key": key,
                        "Value": value,
                    }
                    for key, value in tags_to_add.items()
                ],
            )

    return {}
