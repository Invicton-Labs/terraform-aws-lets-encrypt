#!/usr/bin/env python
import os
import json
import logging
import route53
import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

route53_iam_role = os.environ.get("ROUTE53_IAM_ROLE", None)
route53_policy = os.environ["ROUTE53_POLICY"]
records_file = os.environ["RECORDS_FILE"]
record_prefix = os.environ["RECORD_PREFIX"]
hosted_zones = json.loads(os.environ["HOSTED_ZONES"])
certbot_remaining_challenges = int(os.environ["CERTBOT_REMAINING_CHALLENGES"])

route53_client_default = boto3.client("route53")

if __name__ == "__main__":
    try:
        if certbot_remaining_challenges != 0:
            # Only run cleanup on the last challenge, since it's all done in one go
            exit(0)

        with open(records_file, "r") as file:
            records = json.load(file)

        for domain, tokens in records.items():
            zone = route53.get_hosted_zone_id(hosted_zones, domain)
            zone_id = zone["zone_id"]
            iam_role_arn = zone["iam_role_arn"]
            log.info(
                "Using hosted zone ID %s with IAM role ARN %s for domain %s",
                zone_id,
                iam_role_arn,
                domain,
            )

            route53_client = (
                route53_client_default
                if iam_role_arn is None
                else route53.get_client(role_arn=iam_role_arn, policy=route53_policy)
            )

            route53_client.change_resource_record_sets(
                HostedZoneId=zone_id,
                ChangeBatch={
                    "Changes": [
                        {
                            "Action": "DELETE",
                            "ResourceRecordSet": {
                                "Name": f"{record_prefix}.{domain}",
                                "Type": "TXT",
                                "TTL": 0,
                                "ResourceRecords": [
                                    {"Value": f'"{token}"'} for token in tokens
                                ],
                            },
                        }
                    ]
                },
            )

    except Exception as e:
        log.error("Error in cleanup-hook: %s", str(e))
        exit(1)
