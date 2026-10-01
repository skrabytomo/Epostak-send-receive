# Peppol validation

The application validates UBL Invoice and CreditNote XML before sending.

Validation is selected from the document CustomizationID:

- Peppol BIS Billing 3.0 -> OpenPeppol validation artefacts 2026.5 (BIS Billing 3.0.21)
- PINT EU -> OpenPeppol PINT EU 1.1.1

For PINT EU the validator executes the three applicable Schematron layers supplied by OpenPeppol:

1. EN 16931-specific PINT rules
2. EU Peppol-specific PINT rules
3. Shared PINT rules

The PINT EU release also carries the normative code-list validation used by those artefacts.

The validator engine is PHIVE with the OpenPeppol rule packages. PINT EU 1.1.1 was released 9 June 2026. BIS Billing 3.0.21 was published in May 2026 and became mandatory on 17 August 2026.

## Build

Requirements:

- Java 17+
- Maven

Run build-validator.bat.

The script creates EpostakPeppolValidator.jar in the application directory.

The Delphi application then fails closed: a document is not sent if the local validator is unavailable or if validation reports an error.

## Runtime override

Set EPOSTAK_PEPPOL_VALIDATOR_JAR if the validator JAR is stored elsewhere.
