import logging
import json
import time
import boto3
import os
import tempfile
import route53
import csr
from certbot._internal import main as certbot_main

log = logging.getLogger()
log.setLevel(logging.INFO)

execution_env = os.environ.get("AWS_EXECUTION_ENV", "")
runtime = execution_env.removeprefix("AWS_Lambda_")
hosted_zone_ids = json.loads(os.environ.get("HOSTED_ZONE_IDS", "[]"))
route53_iam_role = os.environ.get("ROUTE53_IAM_ROLE", None)
route53_policy = os.environ.get("ROUTE53_POLICY", "")
default_key_type = os.environ["DEFAULT_KEY_TYPE"]
default_key_size = int(os.environ["DEFAULT_KEY_SIZE"])

# Create an STS client
sts_client = boto3.client("sts")


def deduplicate_domains(domains):
    # Get wildcard subdomains
    wildcard_domains = [domain for domain in domains if domain.startswith("*.")]
    wildcard_base_domains = [domain[2:] for domain in wildcard_domains]

    # It should be included if it's a wildcard domain or if it's not covered by one of the wildcard domains
    return [
        domain
        for domain in domains
        if domain in wildcard_domains
        or domain.split(".", 1)[-1] not in wildcard_base_domains
    ]


def lambda_handler(event, context):
    log.info("Event: %s", json.dumps(event))

    if "key_usages" not in event:
        raise ValueError("The key_usages parameter is required")

    key_usages = event["key_usages"]

    domains = event.get("domains", [])

    domains = deduplicate_domains(domains)
    log.info("Final domain list: %s", domains)

    if len(domains) == 0:
        raise ValueError("At least one domain is required")

    if event.get("add_random_subdomain", False):
        # Add a random subdomain to circumvent the "exact set of identifiers" limit
        domains.append(f"{os.urandom(8).hex()}.{os.urandom(8).hex()}.{domains[0]}")

    # Prepare the CSR
    key_pem, csr_pem = csr.make_csr(
        key_type=event.get("key_type", default_key_type),
        key_size=event.get("key_size", default_key_size),
        key_usages=key_usages,
        common_name=domains[0],
        dns_sans=domains,
    )

    route53_client = route53.get_client(
        role_arn=route53_iam_role, policy=route53_policy
    )

    hosted_zones_by_name = {}
    for zone_id in hosted_zone_ids:
        log.info("Getting hosted zone %s", zone_id)
        response = route53_client.get_hosted_zone(Id=zone_id)
        hosted_zones_by_name[response["HostedZone"]["Name"].rstrip(".")] = zone_id

    os.environ["HOSTED_ZONES"] = json.dumps(hosted_zones_by_name)
    log.info("Hosted zones: \n%s", os.environ["HOSTED_ZONES"])

    log.info("CSR PEM:\n%s", csr_pem)

    result = {}

    with tempfile.TemporaryDirectory() as temp_dir:
        with tempfile.NamedTemporaryFile(mode="w", delete=False) as csr_file:
            cert_file = os.path.join(temp_dir, "cert.pem")
            chain_file = os.path.join(temp_dir, "chain.pem")
            fullchain_file = os.path.join(temp_dir, "fullchain.pem")
            csr_file = tempfile.NamedTemporaryFile(
                mode="wb", delete=False, prefix=temp_dir + "/"
            )
            records_file = tempfile.NamedTemporaryFile(
                mode="w", delete=False, prefix=temp_dir + "/"
            )
            try:
                csr_file.write(csr_pem)
                csr_file.close()
                records_file.write(json.dumps({}))
                records_file.close()

                os.environ["RECORDS_FILE"] = records_file.name
                log.info("Records file: %s", records_file.name)

                script_dir = os.path.dirname(os.path.realpath(__file__))
                auth_hook_path = os.path.join(script_dir, "dns-hook.py")
                cleanup_hook_path = os.path.join(script_dir, "cleanup-hook.py")
                args = [
                    "--config-dir",
                    temp_dir,
                    "--work-dir",
                    temp_dir,
                    "--logs-dir",
                    temp_dir,
                    "--non-interactive",
                    "--agree-tos",
                    "certonly",
                    "--manual",
                    "--preferred-challenges",
                    "dns",
                    "--manual-auth-hook",
                    auth_hook_path,
                    "--manual-cleanup-hook",
                    cleanup_hook_path,
                    "--csr",
                    csr_file.name,
                    "--cert-path",
                    cert_file,
                    "--chain-path",
                    chain_file,
                    "--fullchain-path",
                    fullchain_file,
                ]

                # Run Certbot to get the certificate
                certbot_main.main(args)

                with open(cert_file, "rb") as f:
                    cert_pem = f.read()
                with open(chain_file, "rb") as f:
                    chain_pem = f.read()
                with open(fullchain_file, "rb") as f:
                    fullchain_pem = f.read()

                result = {
                    "cert_pem": cert_pem,
                    "intermediate_chain_pem": chain_pem,
                    "full_chain_pem": fullchain_pem,
                    "key_pem": key_pem,
                    "csr_pem": csr_pem,
                }

            finally:
                # Try deleting all files
                try:
                    os.remove(cert_file)
                except FileNotFoundError:
                    pass
                try:
                    os.remove(chain_file)
                except FileNotFoundError:
                    pass
                try:
                    os.remove(fullchain_file)
                except FileNotFoundError:
                    pass
                try:
                    os.remove(csr_file.name)
                except FileNotFoundError:
                    pass
                try:
                    os.remove(records_file.name)
                except FileNotFoundError:
                    pass

            log.info("Done, returning certificate")
            return result
