# Permission checks

`SiteRepository` requires an explicit SiteID for every role and block query.
`IsAdministrator` matches the account ID, site and actor URI against a current,
enabled account and a current site role. Neither an account from another site
nor a remote actor inherits administrator rights from a shared database or
origin. Deployment and community management authority remain separate scopes.

`SetActorBlocked` and `SetDomainBlocked` require that site's current administrator
and persist the change and site-scoped audit event in one transaction. Queries
use bound parameters. Actor blocks match the exact actor URI; domain blocks
match the normalized hostname exactly, ignoring port, ASCII case and a terminal
dot. Subdomains require their own entries. Unblocking and role revocation take
effect on the next check; these repositories keep no authorization cache.

Personal blocks are a separate, account-scoped view and interaction policy.
`GET`, `POST`, and `DELETE /api/v1/account/blocks` only affect the authenticated
caller at the resolved site. The supported kinds are:

- `person`: an exact canonical Actor URI.
- `community`: a community ID.
- `instance`: a normalized lower-case hostname without a scheme or path.

Adds and removes are idempotent. Self-blocking, blocking the resolved site's own
instance, malformed targets, and unknown or unreadable community targets are
rejected with `400`. Personal block rows are keyed by site, account, kind, and
target, so another account or another site never inherits them.

Personal blocks filter community discovery, latest and community topic feeds,
search results, notifications and unread counts, and saved/read/liked account
listings before pagination. Thread reads omit a blocked reply together with its
descendants, and visible `child_count` values count only surviving children.
A direct read of blocked content returns `404` without returning its body,
author, or count metadata. Blocking does not delete shared posts, reactions, or
notifications, and another account's view is unchanged.

Replies, votes, and mentions recheck the pair relationship in both directions.
A blocked actor receives `403` and the rejected mutation creates no post, vote,
mention row, or notification. A community block can also hide a community and
its content from account listings, but it does not revoke membership or delete
the community.

These account-scoped blocks are not the existing site-administrator
`site_actor_blocks` and `site_domain_blocks`. Administrator blocks protect the
whole site and are managed through site policy; personal blocks protect one
account's experience and remain enabled for every site. The HTTP and storage
acceptance suite covers blocks created before and after content is read, subtree
inheritance, direct-read non-disclosure, interaction rejection, site isolation,
and unblock restoration in `account_blocks_test.mygo`,
`account_blocks_interaction_test.mygo`, and their generated test files.

## Moderation authority

Reports, moderation logs, and bans use separate authority scopes:

- A community manager may review reports and bans scoped to that hosted
  community.
- A site administrator may review all reports, bans, and log entries at that
  site.
- A deployment superadministrator may review the deployment while still acting
  on the site resolved by the request.

Ordinary members cannot list reports or moderation logs, resolve reports, or
change bans. Unauthorized review attempts return `403`; inaccessible or absent
targets return `404`; a conflicting second report resolution returns `409`.
Report resolution and every ban/unban write an append-only moderation-log row.
Site hiding and community removal/restore do the same, while retaining their
existing audit-event trail.

Community bans prevent topic and reply publication, votes, and mention
activation in that community. Site bans are checked during login, session
resolution, and every authenticated mutation. Creating a site ban revokes
current sessions; removing or expiring it permits a new login without changing
an independently disabled account. Expired bans are inactive automatically.

`CommunityPolicy` expresses federation, read and post policy as separate
dimensions. Invalid combinations fail closed.

| Read / post | Local-only | Federated |
| --- | --- | --- |
| eligible_users / eligible_users | Authenticated owning-site accounts read and post | Public read; verified actors post |
| members / members | Approved owning-site members read and post | Verified approved members read and post |
| eligible_users / members | Authenticated owning-site accounts read; members post | Public read; verified approved members post |

All local-only modes deny anonymous, remote and other-site identities, even if
the supplied subject has a membership flag. Membership never enables federation
for local-only content. Blocked subjects receive neither read nor post access.
Federated anonymous readers cannot post, and a revoked member loses any access
requiring membership. Management overrides remain separate from ordinary user
access and require their own scoped authorization and audit.

`AccessSubject` is an internal input, not a client DTO. Callers must establish
identity through a current browser session or verified actor authentication,
and load current membership and block state. A claimed URI or client-supplied
membership/verification flag is not evidence. The pure policy tests exercise
all three combinations, local isolation, verified remote members, revoked
members, anonymous readers, blocked subjects and invalid policy combinations.

These checks are used by the browser and Federation APIs; passing repository and
policy tests does not by itself establish end-to-end restricted federation or
content non-disclosure.
`make test-postgres` additionally verifies site role isolation, actor/domain
block isolation, audit persistence and immediate role/block revocation using
real PostgreSQL alongside the existing authentication suite.

## Current community authority

`CommunityRepository` explicitly selects hosted communities by both community
ID and hosting SiteID. `Check` is an internal authorization snapshot, not a
client response. `Read` returns metadata only after checking current access;
unauthorized readers receive `not found`. Elevated reads are audited.

Enabled local accounts are matched by account ID, site and actor URI. Remote
callers additionally require the service caller's verified-identity assertion
and an existing remote Person actor. This assertion must come from authenticated
transport, not request JSON; signature verification remains pending. A local
account cannot use that remote path to bypass account disablement.

Authority is evaluated in deployment, hosting-site and assigned-community
scope. Community creators and current administrators can manage only their
community. Local-only managers must be owning-site accounts; federated creators
and administrators can be remote Persons. Hosting-site roles and deployment
roles are never inferred for remote managers. Management scope does not confer
ordinary posting membership or permit rewriting another author's content.

`SetMember`, `SetManager` and `SetPolicy` lock the hosted community and perform
current authorization, mutation and audit in one transaction. This serializes
community manager/member/policy changes. Policy updates increment policy_version
and cannot change federation participation. Reads and mutations fetch current
state with no membership, manager or policy cache. The next request therefore
observes revocation even when the browser session remains valid.

An administrative read of a local-only community on another hosted site is
allowed only through explicit deployment authority and is audited; it creates
neither ordinary cross-site membership nor ActivityPub resources. Policy
tightening cannot recall content already delivered publicly. Federation jobs
and protected transport must later recheck the same current state at dispatch.

`community_management_test.mygo` verifies all four role scopes, remote creator
and administrator records, unverified-actor rejection, valid sessions after
membership revocation, manager revocation, disabled creators, policy tightening,
author ownership and deployment audit. These are repository tests rather than
live cross-server management evidence.
