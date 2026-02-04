#!/usr/bin/env python
import os
import json
import time
import logging
import route53

log = logging.getLogger()
log.setLevel(logging.INFO)

route53_iam_role = os.environ.get("ROUTE53_IAM_ROLE", None)
route53_policy = os.environ["ROUTE53_POLICY"]
hosted_zones = json.loads(os.environ["HOSTED_ZONES"])
records_file = os.environ["RECORDS_FILE"]
certbot_domain = os.environ["CERTBOT_DOMAIN"]
certbot_validation = os.environ["CERTBOT_VALIDATION"]
certbot_remaining_challenges = int(os.environ["CERTBOT_REMAINING_CHALLENGES"])
certbot_all_domains = os.environ["CERTBOT_ALL_DOMAINS"]
record_prefix = os.environ["RECORD_PREFIX"]
dns_propagation_delay_seconds = float(os.environ["DNS_PROPAGATION_DELAY_SECONDS"])

if __name__ == "__main__":
    all_domains = [domain.strip() for domain in certbot_all_domains.split(",")]
    challenge_idx = len(all_domains) - certbot_remaining_challenges - 1
    log.info("Challenge index: %d", challenge_idx)
    log.info("CERTBOT_DOMAIN: %s", certbot_domain)
    log.info("CERTBOT_VALIDATION: %s", certbot_validation)
    log.info("CERTBOT_REMAINING_CHALLENGES: %d", certbot_remaining_challenges)
    log.info("CERTBOT_ALL_DOMAINS: %s", certbot_all_domains)
    
    with open(records_file, 'r') as file:
        records = json.load(file)

    if certbot_domain in records:
        records[certbot_domain].append(certbot_validation)
    else:
        records[certbot_domain] = [certbot_validation]

    # There are still more challenges, so just write the file and exit
    with open(records_file, 'w') as file:
        json.dump(records, file)

    log.info("New records file: \n%s", json.dumps(records, indent=2))

    if certbot_remaining_challenges != 0:
        exit(0)

    # This is the last challenge, it's time to write to Route53
    route53_client = route53.get_client(role_arn=route53_iam_role, policy=route53_policy)

    for domain, tokens in records.items():
        zone_id = route53.get_hosted_zone_id(hosted_zones, domain)

        route53_client.change_resource_record_sets(
            HostedZoneId=zone_id,
            ChangeBatch={
                'Changes': [
                    {
                        'Action': 'UPSERT',
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

    time.sleep(dns_propagation_delay_seconds)
