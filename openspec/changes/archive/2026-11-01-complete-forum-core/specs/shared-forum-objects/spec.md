## ADDED Requirements

### Requirement: Shared vote state
Each post and reply SHALL retain at most one active vote per reacting Actor, with values `-1` and `1`; clearing a vote removes its contribution. The shared object SHALL expose aggregate `score`, `upvotes`, and `downvotes` computed from active votes known at the resolved site. Votes SHALL NOT be copied into a second logical post, and different receiving sites SHALL remain able to record independent reception while sharing the object's vote state where the protocol provides it. A vote SHALL NOT grant read access, membership, or editing authority.

#### Scenario: One actor changes vote
- **WHEN** the same actor changes an upvote to a downvote on a shared object
- **THEN** the object has one active downvote and the aggregate score changes by two

#### Scenario: Vote does not grant access
- **WHEN** an actor can read a public object but not a restricted object and attempts to vote on the restricted one
- **THEN** the vote is rejected without granting access

### Requirement: Dislike activity support
The federation layer SHALL accept and emit ActivityPub `Like`, `Dislike`, and their `Undo` activities for posts and replies. Inbound activities SHALL require the existing signature, actor, object, and community authority checks, SHALL be idempotent by activity identity, and SHALL NOT be accepted from a blocked actor. Outbound vote activities SHALL be delivered only for federated objects and eligible recipients; local-only objects SHALL produce no activity. Unknown extensions SHALL NOT bypass vote authorization or duplicate an active vote.

#### Scenario: Dislike and undo
- **WHEN** a signed remote `Dislike` is followed by a signed `Undo` of that activity
- **THEN** the object first records a downvote and then clears it

#### Scenario: Blocked voter
- **WHEN** a site-blocked actor sends a `Like` or `Dislike`
- **THEN** the activity is rejected and no vote is stored

#### Scenario: Local-only vote
- **WHEN** a local account votes on a local-only post
- **THEN** no federation activity or delivery job is created
