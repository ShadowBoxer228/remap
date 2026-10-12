# Security

Keep security reports private. Use **Security → Report a vulnerability** in this
repository when available. Do not post working credentials, private documents,
recordings, installation proofs or personal data in public issues.

Include the affected component, a minimal reproduction with synthetic data, the
impact and tested revision. There is no published response-time guarantee.

## Credentials and local files

Real environment files, signing keys, provisioning profiles, app archives, local
agent transcripts and release evidence do not belong in Git. `.env.example`
contains names only. Store deployment credentials in the provider's secret storage.

Public Apple root certificates, bundle identifiers and example credentials are
not private keys. Never use an example value in production.

If a real credential is exposed, revoke or rotate it first. Removing it from the
latest file or rewriting history does not invalidate existing copies.

## Service scope

This code includes internal TestFlight enrollment. Publishing the source does not
make the hosted API an unrestricted public service. Independent deployments need
their own credentials, access policy and budgets.

Model output is untrusted: map changes pass server and native validation. Document
text and tool output must not override authentication, allowed operations or the
user's requested scope.
