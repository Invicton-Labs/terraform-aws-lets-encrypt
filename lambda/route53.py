import boto3
import logging

log = logging.getLogger()
log.setLevel(logging.INFO)

sts_client = boto3.client('sts')

def get_client(role_arn=None, policy=None):
    if role_arn:
        log.info("Assuming role: %s", role_arn)
        # Assume the specified IAM role
        assumed_role = sts_client.assume_role(
            RoleArn=role_arn,
            RoleSessionName="LetsEncryptSession",
            Policy=policy
        )
        credentials = assumed_role['Credentials']

        # Create a Route53 client using the assumed role's temporary credentials
        route53_client = boto3.client(
            'route53',
            aws_access_key_id=credentials['AccessKeyId'],
            aws_secret_access_key=credentials['SecretAccessKey'],
            aws_session_token=credentials['SessionToken']
        )
    else:
        # Create a Route53 client using the default credentials
        route53_client = boto3.client('route53')

    return route53_client


def get_hosted_zone_id(hosted_zones: dict[str, str], domain: str):
    best_match_zone_id = None
    best_match_length = -1
    for zone_domain, zone_id in hosted_zones.items():
        # Use this zone if the domain matches exactly or is a subdomain of the zone, 
        # and it's a more specific match than anything found so far
        if (domain == zone_domain or domain.endswith(f".{zone_domain}")) and len(zone_domain) > best_match_length:
            best_match_zone_id = zone_id
            best_match_length = len(zone_domain)

    if not best_match_zone_id:
        raise ValueError(f"No hosted zone found for domain: {domain}")
    
    return best_match_zone_id