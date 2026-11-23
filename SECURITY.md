# Security policy

## Scope

This is a portfolio and reference project. It is not a certified or
compliance-validated product. The STIG-aligned Puppet module covers a small
subset of controls and has not been scanned on a real RHEL host.

## Reporting a vulnerability

Open a private security advisory on the GitHub repository
(Security tab, "Report a vulnerability"). Do not open a public issue for
anything that looks exploitable. Expect a reply within a week.

## Handling of secrets

No credentials, tokens, or keys belong in this repository. Examples use
placeholders such as `CHANGE_ME` and `registry.example.internal`. Pass real
Harbor and Keycloak secrets through your secret store at deploy time.
