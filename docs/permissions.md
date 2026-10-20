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

These checks are building blocks. Management HTTP APIs and ActivityPub delivery
have not yet been implemented; passing repository and policy tests does
not establish end-to-end restricted federation or content non-disclosure.
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
