## Purpose

Let an account owner recover access after forgetting a password through a single-use email link, and let an authenticated owner change a known password safely.

## ADDED Requirements

### Requirement: Reset request without account enumeration
`POST /api/v1/auth/password/reset` SHALL accept a JSON body containing `email` and SHALL return `202` with a generic acceptance response for a syntactically valid address, whether or not an account exists. It SHALL return `400` for an invalid body or address, `403` for an invalid origin, and `429` when a configured per-site client-IP or normalized-email limit is exceeded. The endpoint SHALL work for existing accounts even when public registration is disabled. It SHALL NOT accept a password, reveal whether the address exists, or disclose account roles, site membership, or token state. Requests SHALL be site-scoped by the resolved HTTP authority.

#### Scenario: Unknown address
- **WHEN** a client submits a valid address with no account
- **THEN** the response is the same generic `202` as for a known address and no mail job is created

#### Scenario: Disabled registration
- **WHEN** an existing account requests a reset while public registration is disabled
- **THEN** the request is accepted and a reset link can still be delivered

#### Scenario: Rate limited
- **WHEN** a client exceeds the configured reset rate limit
- **THEN** the server returns `429` with `Retry-After` and creates no additional reset token

### Requirement: Single-use expiring reset tokens
Reset tokens SHALL be unpredictable, bound to one site and account, stored only as digests in the reset record, and delivered through an encrypted durable mail job. A token SHALL expire after the configured reset lifetime, SHALL be consumed atomically, and SHALL NOT be reusable after a successful confirmation. A new request SHALL invalidate the account's preceding unused reset token. Mail delivery SHALL survive worker restarts, retry transient failures within configured bounds, and SHALL NOT log token plaintext or passwords. A token issued for one site SHALL NOT confirm an account at another site.

#### Scenario: Concurrent confirmation
- **WHEN** two requests confirm the same valid token concurrently
- **THEN** exactly one changes the password and the other fails without a second change

#### Scenario: Resend invalidates the old link
- **WHEN** a second reset is requested before the first link is used
- **THEN** only the newest token can change the password

#### Scenario: Expired or cross-site token
- **WHEN** a client submits an expired token or a token issued for another site
- **THEN** the server returns `400` and the account password is unchanged

### Requirement: Reset confirmation and authenticated change
`POST /api/v1/auth/password/reset/confirm` SHALL accept `token` and `password`, enforce the existing 12-to-72-byte password rule, atomically install the new hash, consume the token, and revoke every existing session for that account. Success SHALL return `204`; an invalid, expired, reused, or cross-site token, or an invalid password, SHALL return `400` without consuming a valid token when the password is invalid. `POST /api/v1/auth/password/change` SHALL require a current session, same-origin validation, and CSRF, accept `current_password` and `new_password`, verify the current password, install the new hash, revoke other sessions, and return `204`. It SHALL return `401` without a session, `403` for origin or CSRF failure, and `400` for a wrong current password or invalid new password.

#### Scenario: Reset revokes sessions
- **WHEN** a user completes a valid reset confirmation
- **THEN** all previously issued sessions for that account are revoked and the old password no longer authenticates

#### Scenario: Invalid final password keeps token
- **WHEN** a user submits a valid token with a too-short password
- **THEN** the request returns `400` and the token remains usable for a valid password

#### Scenario: Authenticated change
- **WHEN** an authenticated user supplies the correct current password and a valid new password
- **THEN** the new password authenticates, other sessions are revoked, and the current session remains valid
