# group-federation Specification

## Purpose

Implement FEP-1b12 for federated communities with access-aware membership, verified cross-server management, and group-approved distribution.

## Requirements

### Requirement: Group identity and audience
Each federated community SHALL be represented by a Group actor with stable identity and access-controlled collection endpoints. Federated topics and replies and their related activities SHALL identify the community through audience and appropriate delivery addressing; replies SHALL retain inReplyTo. Receiving a claimed audience SHALL NOT by itself prove community approval. Local-only communities SHALL have no exposed Group representation or federation workflow.

#### Scenario: Resolve a reply's community
- **WHEN** a peer retrieves a local reply
- **THEN** its audience identifies the Group and its inReplyTo identifies the direct parent

### Requirement: Federated group subscriptions
Federated communities SHALL implement Follow, Accept of eligible Follow, and authenticated Undo of Follow. Openly readable communities SHALL support ordinary subscription admission; member-readable communities SHALL require approved read access before Accept and content delivery. Membership granting posting or restricted reading SHALL be tracked separately from following; a Follow request alone SHALL NOT confer membership. Accepted subscribers SHALL receive only distribution eligible under current policy. Undo SHALL remove only the issuing actor's subscription, without implicitly removing separately granted community membership.

#### Scenario: Subscribe then unsubscribe
- **WHEN** a remote actor follows a public community and later validly undoes that Follow
- **THEN** the community accepts the initial subscription and stops scheduling new subscriber deliveries after unsubscribe

### Requirement: Validated intact forwarding
A federated community SHALL validate incoming content activities against identity, authorship, community association, posting policy, and applicable blocks or moderation rules. Accepted content activities SHALL be wrapped intact in a Group-authored Announce, added to its access-controlled outbox, and scheduled only for eligible subscribers. All original properties, including unknown extensions and integrity proofs, SHALL be preserved. A member-readable community SHALL reject a submission whose addressing or embedded representation would expose content publicly rather than rewrite it silently. Rejected activities SHALL NOT enter accepted collections or be forwarded. Subscription control activities SHALL NOT be broadcast as content.

#### Scenario: Forward an extended activity
- **WHEN** a valid Create contains unknown extension properties and an integrity proof
- **THEN** the community's Announce contains the unchanged original activity and schedules it for eligible followers

#### Scenario: Blocked submitter
- **WHEN** a blocked actor submits a topic
- **THEN** it is not accepted or announced and the rejection is recorded

### Requirement: Verified group approval and moderation
Followers SHALL verify the announcing Group and its association with the inner activity before recording community approval. Federated communities SHALL represent creator and community-administrator authority and expose eligible manager identities through the Group's attributedTo collection under its read policy. Received management SHALL require verified creator, community-administrator, applicable hosting-site administrator, or hosting-deployment superadministrator authority; followers SHALL additionally require the community's verified Announce. Creator and community-administrator actors SHALL be eligible to reside on another server, without gaining site or deployment permissions. Merely sharing a hostname or presenting a valid signature SHALL NOT establish management authority.

#### Scenario: Forged community announcement
- **WHEN** an unrelated actor announces a post claiming another community's audience
- **THEN** the receiver does not record that other community's approval

#### Scenario: Non-moderator removal
- **WHEN** an actor outside the verified moderators and applicable hosting-site authority requests removal
- **THEN** the community rejects the moderation activity

#### Scenario: Authorized community removal received by a follower
- **WHEN** a verified community announces a verified moderator's removal of a community post
- **THEN** the follower removes community inclusion without globally deleting the author's shared object

### Requirement: Federated access modes and remote management
Federated communities SHALL support openly readable content with posting by eligible authenticated actors, members-only reading and posting, and openly readable content with members-only posting. Hosts SHALL enforce posting and membership policy for both local and remote actors. Verified remote creators and community administrators SHALL be able to manage metadata, read/post policy, members, community administrators, and scoped moderation through the same community authority rules. Revoked roles SHALL cease to authorize new actions. Instance administrators of an unrelated server SHALL NOT gain authority over the hosted community.

#### Scenario: Subscriber without posting membership
- **WHEN** a remote subscriber attempts to post in an openly readable members-posting community without approved membership
- **THEN** reading remains permitted but the submission is rejected

#### Scenario: Remote community creator
- **WHEN** a verified creator hosted on server A changes their community metadata on server B
- **THEN** B accepts and announces the authorized change without granting the creator B's site administration role

#### Scenario: Remote community administrator removed
- **WHEN** a previously authorized remote community administrator sends a new management action after role revocation
- **THEN** the host rejects it even if its signature remains valid

#### Scenario: Non-member requests restricted subscription
- **WHEN** a remote non-member follows a member-readable community
- **THEN** no content subscription is accepted until membership or applicable management read authority is approved

