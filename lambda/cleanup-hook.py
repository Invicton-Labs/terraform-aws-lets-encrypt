#!/usr/bin/env python
import os
import json
import logging
import route53

log = logging.getLogger()
log.setLevel(logging.INFO)

route53_iam_role = os.environ.get("ROUTE53_IAM_ROLE", None)
route53_policy = os.environ["ROUTE53_POLICY"]
records_file = os.environ["RECORDS_FILE"]
record_prefix = os.environ["RECORD_PREFIX"]
hosted_zones = json.loads(os.environ["HOSTED_ZONES"])
certbot_remaining_challenges = int(os.environ["CERTBOT_REMAINING_CHALLENGES"])

if __name__ == "__main__":
    if certbot_remaining_challenges != 0:
        # Only run cleanup on the last challenge, since it's all done in one go
        exit(0)

    with open(records_file, 'r') as file:
        records = json.load(file)

    route53_client = route53.get_client(role_arn=route53_iam_role, policy=route53_policy)

    for domain, tokens in records.items():
        zone_id = route53.get_hosted_zone_id(hosted_zones, domain)
        route53_client.change_resource_record_sets(
            HostedZoneId=zone_id,
            ChangeBatch={
                'Changes': [
                    {
                        'Action': 'DELETE',
                        'ResourceRecordSet': {
                            'Name': f"{record_prefix}.{domain}",
                            'Type': 'TXT',
                            'TTL': 0,
                            'ResourceRecords': [{'Value': f'"{token}"'} for token in tokens]
                        }
                    }
                ]
            }
        )
