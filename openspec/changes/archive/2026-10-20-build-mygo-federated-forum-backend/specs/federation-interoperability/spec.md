## Purpose

Establish tested compatibility with Commune, Lemmy, Mastodon, and Misskey using explicit public-forum interaction profiles and reproducible evidence.

## ADDED Requirements

### Requirement: Ordered compatibility acceptance
Interoperability SHALL be accepted in order: independent Commune server instances, Lemmy, Mastodon, and Misskey. All four targets SHALL remain required for completing this change. Each profile SHALL record exact tested releases or commits, protocol references, scenario outcomes, and known peer limitations; fixture-only success SHALL NOT be described as live interoperability.

#### Scenario: Report profile results
- **WHEN** a compatibility milestone is reviewed
- **THEN** its evidence identifies peer versions and distinguishes live tests, fixture tests, failures, and unsupported peer capabilities

### Requirement: Commune end-to-end federation
Two independent Commune deployments SHALL discover eligible actors and communities, subscribe and unsubscribe, publish topics and nested replies, forward community activities, update and delete authored objects, like and undo likes, apply verified community management, and resolve/backfill eligible contexts. All three access modes SHALL be tested, including positive member-readable federation and creators/administrators managing across servers. The suite SHALL also cover all local-only modes, two sites sharing one database, scoped deployment/site roles, and negative authority, revocation, disclosure, and replay cases.

#### Scenario: Independent instances exchange a discussion
- **WHEN** an account on instance A subscribes to a community on B and publishes a topic and replies there
- **THEN** B accepts and announces eligible content and A receives consistent identities, reply links, and accepted context membership

#### Scenario: Protected discussion and remote management
- **WHEN** approved members at A and B participate in a member-readable community hosted at B and its verified creator or administrator acts from A
- **THEN** authorized discussion and management propagate while anonymous callers, non-members, and unrelated server administrators receive no protected content or authority

### Requirement: Lemmy forum compatibility
The Lemmy profile SHALL support bidirectional community discovery, Follow and Accept, topics, nested comments, community Announce, authored updates and deletion, likes and undo, and community moderation removal for the pinned release. It SHALL accept Page topics and Note comments and preserve required audience, title, and parent relationships. Missing context from Lemmy SHALL NOT invalidate supported content.

#### Scenario: Round-trip Lemmy thread
- **WHEN** a Commune account posts and comments in a Lemmy community and a Lemmy account posts and comments in a Commune community
- **THEN** both sides display the intended community, title, authors, and reply relationships and propagate supported edits and removals

### Requirement: Mastodon and Misskey public interaction compatibility
Each microblog profile SHALL support bidirectional actor discovery, Person following and unfollowing, public post delivery and retrieval, replies, authored updates and deletion, likes and undo, and ordinary object Announce ingestion. Commune SHALL accept supported Note-based submissions to explicitly addressed eligible federated communities subject to posting policy. Topic representations and group fan-out SHALL be validated against each peer's actual capabilities without changing canonical identity or modifying the inner FEP-1b12 activity. Public compatibility paths SHALL NOT export local-only or member-readable objects.

#### Scenario: Reply from a microblog account
- **WHEN** a Mastodon or Misskey account replies to a supported Commune public object
- **THEN** Commune retains the remote author and parent identity and applies validated community and context association without requiring unsupported peer fields

#### Scenario: Unsupported native group envelope
- **WHEN** a pinned peer cannot consume a nested FEP-1b12 community Announce
- **THEN** its profile demonstrates a tested public user-to-user or conventional object-sharing route for supported interactions, records the group limitation, and does not claim native group support

### Requirement: Extension tolerance and negative coverage
Unknown extension fields SHALL be preserved when forwarding and handled without corrupting supported identities or relationships. Every profile SHALL include duplicate receipt and unauthorized mutation cases. Optional polls, custom reactions, and platform-client APIs SHALL NOT be prerequisites for basic forum interoperability, and their unsupported status SHALL be explicit.

#### Scenario: Optional extension encountered
- **WHEN** an otherwise supported remote Note includes an unsupported platform-specific extension
- **THEN** supported text and reply processing succeeds, permissions remain unchanged, and intact community forwarding retains that extension

### Requirement: Access-control interoperability gates
All peer profiles SHALL verify that local-only communities never participate in ActivityPub regardless of their local read/post mode. Member-readable federation SHALL require a tested peer profile for actor authorization, member-directed delivery, protected cache access, and context retrieval. Unsupported external profiles SHALL remain explicitly incompatible with restricted communities and SHALL receive no restricted data; required public interoperability SHALL remain in scope. Cross-server management support and limitations SHALL be recorded separately from content compatibility.

#### Scenario: Unsupported restricted peer
- **WHEN** a peer passes public content tests but fails member-scoped protected retrieval or cache authorization
- **THEN** public interoperability is reported separately and restricted delivery to that peer is denied without changing community policy

#### Scenario: Local-only exclusion across all peers
- **WHEN** any target peer follows an author, guesses a local-only resource, or targets it through a signed activity
- **THEN** no local-only community metadata, object, context, count, or activity reaches the peer
