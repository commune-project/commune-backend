# site-isolation Specification

## Purpose

Keep account authentication, authorization, and site policy independent while multiple domains use the same server and database.

## Requirements

### Requirement: Trusted site routing
Every site request SHALL resolve to a configured site through a normalized authority. Unknown hosts SHALL be rejected. Forwarded host information SHALL affect routing only through an explicitly trusted proxy configuration. Public identifiers SHALL use the configured canonical origin rather than an arbitrary request header.

#### Scenario: Unknown request host
- **WHEN** a request names an unconfigured host
- **THEN** the server rejects it without selecting a default site's data

#### Scenario: Untrusted forwarded host
- **WHEN** a client outside the trusted proxy configuration supplies a forwarded host header
- **THEN** the header does not change the resolved site or generated public identifiers

### Requirement: Independent site accounts
Each site SHALL maintain independent accounts, password authentication, sessions, and roles. Usernames and optional login email addresses SHALL be unique within a site; identical values SHALL be permitted across sites. Authentication SHALL search only within the resolved site and SHALL return a generic failure for invalid credentials.

#### Scenario: Same username at two sites
- **WHEN** site A and site B each provision an account named alice with different passwords
- **THEN** each password authenticates only its corresponding site's account

#### Scenario: Session replay across sites
- **WHEN** a valid session issued by site A is presented to site B
- **THEN** it grants no authenticated identity or privileges at site B

### Requirement: Protected browser authentication
Password material SHALL be stored using a password hashing scheme. Browser sessions SHALL expire, be revocable, and use secure host-scoped cookies. Cookie-authenticated mutations SHALL enforce CSRF protection. Logout SHALL revoke the session.

#### Scenario: Cross-origin mutation
- **WHEN** a cookie-authenticated mutation lacks valid CSRF protection
- **THEN** it is rejected without changing forum data

### Requirement: Site-scoped policy and access
Site administration, actor and domain blocks, content hiding, and local reception state SHALL be scoped to the resolved site. Shared storage SHALL NOT grant site membership or access. Public canonical origin resources SHALL remain retrievable at their owning site's canonical URI subject to that site's policy. A deployment superadministrator SHALL require an explicitly assigned deployment-wide role; ordinary site roles SHALL NOT acquire that authority.

#### Scenario: Local hide at one site
- **WHEN** site A hides a shared remote post that site B also received
- **THEN** site A's listing omits it while site B's listing and the shared object remain unaffected

#### Scenario: Unreceived object ID
- **WHEN** a user requests a shared remote object's local ID through a site that has not received or explicitly imported it
- **THEN** the site does not expose it merely because another site stored it

### Requirement: Independent community access dimensions
Community federation participation SHALL be independent of read/post access policy and management roles. Local-only communities SHALL support three modes: all authenticated owning-site users can read and post; only approved members can read and post; or all authenticated owning-site users can read while only approved members can post. Anonymous users, remote actors, and ordinary accounts of another site SHALL NOT receive local-only community access. Explicit audited deployment administration SHALL remain a separate scoped authority, not cross-site user membership. Membership SHALL be evaluated independently of subscriptions and management assignments.

#### Scenario: Site-wide local community
- **WHEN** a non-member authenticates at the owning site of an all-site-users read/write community
- **THEN** that account can read and post without joining, but an account of another colocated site cannot

#### Scenario: Members-only local community
- **WHEN** an owning-site user without approved membership requests a members-only community or its posts
- **THEN** no community metadata or content is disclosed and posting is denied

#### Scenario: Site-wide readers with member writers
- **WHEN** an owning-site non-member accesses a community configured for all-site-users read and members-only posting
- **THEN** reading is permitted and topic or reply creation is denied

### Requirement: Scoped management roles
The system SHALL distinguish deployment superadministrator, site administrator, community creator, and community administrator. A superadministrator SHALL administer hosted sites and communities; a site administrator SHALL administer only their site and its hosted communities; a creator and a community administrator SHALL administer only their assigned community, including membership, metadata, access policy, and moderation. Administrative access SHALL be authorized and audited in its applicable scope. Community administration SHALL NOT authorize rewriting another author's shared content or changing a higher-scope role. A community creator or administrator of a local-only community SHALL be an account of its owning site.

#### Scenario: Site administrator crosses a tenant boundary
- **WHEN** a site A administrator attempts to manage a site B community without another applicable role
- **THEN** the request is rejected even when both sites share the same database

#### Scenario: Explicit deployment-wide administrator
- **WHEN** an explicitly provisioned superadministrator manages a community on another hosted site
- **THEN** the action is permitted in deployment scope and recorded with the acting identity

#### Scenario: Community administrator escalates privileges
- **WHEN** a community administrator attempts to assign a site or deployment administrator role
- **THEN** the request is rejected without changing higher-scope roles

### Requirement: Current membership and policy enforcement
Authorized community managers SHALL be able to approve and remove members and assign or revoke community administrators within their scope. Every read and mutation SHALL evaluate current membership, management authority, and access policy. Policy or membership changes SHALL invalidate access caches and SHALL affect new requests and pending delivery. Historical authorship or a valid session SHALL NOT bypass revoked read access.

#### Scenario: Removed member retains a valid session
- **WHEN** a removed member with no management authority requests their previous post in a members-only community
- **THEN** the request is denied despite historical authorship and a valid login

#### Scenario: Tighten posting policy
- **WHEN** an authorized manager changes a local community from all-site-users posting to members-only posting
- **THEN** subsequent non-member posting is rejected without requiring those accounts to log out

