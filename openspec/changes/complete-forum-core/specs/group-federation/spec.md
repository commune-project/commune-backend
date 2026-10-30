## ADDED Requirements

### Requirement: Browser-initiated community follows
A browser follow of a federated community that is admitted by the hosted policy SHALL create or update the local follow intent and SHALL queue an Actor-signed `Follow` addressed to the Group. A follow rejected by a `members` or `disabled` policy SHALL NOT queue an activity. A browser unfollow SHALL queue an `Undo` of the accepted or pending follow. An inbound `Accept` or `Reject` SHALL update the follow state for the matching local Actor and follow activity. A duplicated or replayed response SHALL NOT create a second follow or undo a newer follow. Local-only communities SHALL process follows locally without federation. The existing person-follow behavior SHALL remain separate from community follows.

#### Scenario: Follow sends activity
- **WHEN** a local account follows a federated open community
- **THEN** the follow is accepted locally and one signed `Follow` is queued for the Group

#### Scenario: Remote acceptance
- **WHEN** the Group returns a signed `Accept` for that follow
- **THEN** the local follow remains accepted and no duplicate delivery is created

#### Scenario: Local-only follow
- **WHEN** a local account follows a local-only community
- **THEN** the follow is stored locally and no federation activity is created

### Requirement: Federated follows honor community policy
Inbound `Follow` handling SHALL use the hosted community's current `follow_policy`. `open` SHALL accept an eligible follower. `members` SHALL accept a current approved member or manager and SHALL reject another actor. `approval` SHALL accept a current member or manager and SHALL create a pending request for another eligible actor. `disabled` SHALL reject every new follow and SHALL NOT create a pending or accepted row. Existing accepted followers SHALL remain when a policy changes. A rejected follow SHALL receive a signed `Reject` when the protocol permits a response, and a pending follow SHALL NOT be represented as accepted in the Group's follower count.

#### Scenario: Open federated follow
- **WHEN** an eligible remote actor follows an open federated community
- **THEN** the follow is accepted and appears in the Group follower count

#### Scenario: Members-only federated follow
- **WHEN** a non-member remote actor follows a community whose policy is `members`
- **THEN** the follow is rejected and no membership is created

#### Scenario: Disabled federated follow
- **WHEN** a remote actor follows a community whose policy is `disabled`
- **THEN** the follow is rejected and no pending row is created

### Requirement: Approval policy review and membership
For a community whose follow policy is `approval`, a follow from an eligible non-member SHALL be pending until a manager accepts or rejects it. Existing pending rows SHALL remain reviewable after a policy change; new pending rows SHALL be created only while the policy is `approval`. Acceptance SHALL atomically establish an accepted follow and approved membership; rejection SHALL establish a rejected follow without membership. The manager action SHALL write an audit event and SHALL queue a signed `Accept` or `Reject` for a federated follower. A pending follow SHALL NOT grant read access, posting, voting, or notification eligibility. The Group representation's follower count SHALL count accepted follows only.

#### Scenario: Pending approval follow
- **WHEN** a non-member follows an `approval` federated community
- **THEN** the follow is pending, no membership exists, and the Group has not accepted the follower

#### Scenario: Acceptance grants access
- **WHEN** a manager accepts the pending follow
- **THEN** the follower becomes an approved member, the follow becomes accepted, and the Group sends an `Accept`

#### Scenario: Rejection does not grant access
- **WHEN** a manager rejects the pending follow
- **THEN** no membership is created, the follow becomes rejected, and the Group sends a `Reject`
