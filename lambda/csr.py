from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID

def make_private_key(kind: str, size: int):
    """
    kind: "ec" (P-256/384) or "rsa" (2048/3072/4096)
    """
    if kind == "ec":
        if size == 256:
            return ec.generate_private_key(ec.SECP256R1())
        if size == 384:
            return ec.generate_private_key(ec.SECP384R1())
        else:
            raise ValueError("For EC keys, size must be 256 or 384")
    elif kind == "rsa":
        if size not in (2048, 3072, 4096):
            raise ValueError("For RSA keys, size must be 2048, 3072, or 4096")
        return rsa.generate_private_key(public_exponent=65537, key_size=size)
    else:
        raise ValueError("Key type must be 'ec' or 'rsa'")


def make_csr(
    key_type: str,
    key_size: int,
    key_usages: list[str],
    common_name: str,
    organization: str | None = None,
    organizational_unit: str | None = None,
    country: str | None = None,
    state_or_province: str | None = None,
    locality: str | None = None,
    email: str | None = None,
    dns_sans: list[str] | None = None,
) -> tuple[any, x509.CertificateSigningRequest]:
    
    # Subject (a.k.a. "distinguished name")
    subject_parts: list[x509.NameAttribute] = [
        x509.NameAttribute(NameOID.COMMON_NAME, common_name),
    ]
    if organization:
        subject_parts.append(x509.NameAttribute(NameOID.ORGANIZATION_NAME, organization))
    if organizational_unit:
        subject_parts.append(x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, organizational_unit))
    if locality:
        subject_parts.append(x509.NameAttribute(NameOID.LOCALITY_NAME, locality))
    if state_or_province:
        subject_parts.append(x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, state_or_province))
    if country:
        subject_parts.append(x509.NameAttribute(NameOID.COUNTRY_NAME, country))
    if email:
        subject_parts.append(x509.NameAttribute(NameOID.EMAIL_ADDRESS, email))

    builder = x509.CertificateSigningRequestBuilder().subject_name(x509.Name(subject_parts))

    # SAN extension
    san_entries: list[x509.GeneralName] = []
    for d in (dns_sans or []):
        san_entries.append(x509.DNSName(d))

    if san_entries:
        builder = builder.add_extension(x509.SubjectAlternativeName(san_entries), critical=False)

    # Optional but commonly requested extensions for TLS leaf certs:
    builder = builder.add_extension(
        x509.KeyUsage(
            digital_signature='digitalSignature' in key_usages,
            key_encipherment='keyEncipherment' in key_usages,
            content_commitment='contentCommitment' in key_usages or 'nonRepudiation' in key_usages,
            data_encipherment='dataEncipherment' in key_usages,
            key_agreement='keyAgreement' in key_usages,
            key_cert_sign='keyCertSign' in key_usages,
            crl_sign='cRLSign' in key_usages,
            encipher_only='encipherOnly' in key_usages,
            decipher_only='decipherOnly' in key_usages,
        ),
        critical=True,
    )
    
    # Add extended key usages
    extended_key_usages = []
    if 'serverAuth' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.SERVER_AUTH)
    if 'clientAuth' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.CLIENT_AUTH)
    if 'codeSigning' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.CODE_SIGNING)
    if 'emailProtection' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.EMAIL_PROTECTION)
    if 'timestamping' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.TIME_STAMPING)
    if 'ocspSigning' in key_usages:
        extended_key_usages.append(ExtendedKeyUsageOID.OCSP_SIGNING)

    if len(extended_key_usages) > 0:
        builder = builder.add_extension(
            x509.ExtendedKeyUsage(extended_key_usages),
            critical=False,
        )

    private_key = make_private_key(kind=key_type, size=key_size)

    # Sign the CSR
    csr = builder.sign(private_key, hashes.SHA256())

    key_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM)

    return key_pem, csr_pem
