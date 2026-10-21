## Purpose

Allow ordinary users to create site-local accounts after proving control of an email address, with reliable delivery and bounded abuse exposure.

## ADDED Requirements

### Requirement: Site-controlled verified registration
Public registration SHALL be explicitly enabled per site and disabled by default. Initial registration SHALL accept only a valid site-unique username and normalized site-unique email; it SHALL NOT accept or retain a password. Email confirmation SHALL require a valid verification token and a final password meeting existing account rules, and SHALL atomically create the account and Actor using that password. A pending registration SHALL NOT authenticate, receive roles, or create a public Actor until verification succeeds. Existing provisioned accounts SHALL remain usable without retroactive email verification. The same username or email at another site SHALL remain independent.

#### Scenario: Pending account cannot log in
- **WHEN** a user submits valid registration data at an enabled site but has not verified the email
- **THEN** login fails and no discoverable Actor or administrator grant exists

#### Scenario: Site isolation and disabled registration
- **WHEN** a registration is attempted at a disabled site or a token issued for another site is submitted
- **THEN** the operation is rejected without creating or activating an account

#### Scenario: Password chosen by the verifying email owner
- **WHEN** another party initially submits an email owner's address and that owner later completes verification
- **THEN** only the password supplied by the owner with the valid token is installed, and no initial or resend request can install credentials

### Requirement: Single-use verification and safe delivery
Verification SHALL use unpredictable expiring tokens, store only token digests in verification records, and atomically consume a valid token when creating the account and Actor. Resend SHALL invalidate preceding tokens. Invalid, expired, reused, and cross-site tokens SHALL NOT activate an account. Registration and resend SHALL return the same accepted response for otherwise valid input regardless of existing email ownership. Mail delivery SHALL survive worker restarts, retry transient failure with bounds, and avoid logging tokens or credentials. Registration and resend SHALL enforce configured per-site client-IP and normalized-email limits and return 429 when exceeded.

#### Scenario: Concurrent verification
- **WHEN** two requests redeem the same valid token concurrently
- **THEN** exactly one account and Actor are created and the token cannot be consumed twice

#### Scenario: Resend and mail retry
- **WHEN** a resend replaces a token and SMTP temporarily fails
- **THEN** only the replacement token can activate the account and delivery can retry without creating another account
