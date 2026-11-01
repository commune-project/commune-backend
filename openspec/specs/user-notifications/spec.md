# user-notifications Specification

## Purpose

Keep site-local users informed of replies, likes, and mentions with durable deduplicated records and permission-aware unread state.

## Requirements

### Requirement: Durable authorized notifications
Accepted local actions and verified remote activities SHALL generate notifications for direct replies to a user's post, active likes on that user's post, and valid mentions of that user. Recipients SHALL be local accounts of the receiving site and SHALL have current access to the target. Self-actions SHALL NOT notify. Replayed activities and retried workers SHALL NOT duplicate notifications. Notification creation SHALL follow committed actions through an atomic event or equivalent durable mechanism. Undoing a like, removing a mention, or deleting a target SHALL retire the corresponding active notification; a later distinct re-like SHALL be eligible to notify again.

#### Scenario: Duplicate remote delivery
- **WHEN** the same accepted activity arrives repeatedly or a notification worker retries
- **THEN** a recipient has at most one notification for that logical event and kind

#### Scenario: Reply also mentions its parent author
- **WHEN** one reply both replies to and mentions the same recipient
- **THEN** one notification is shown with mention taking precedence over reply

### Requirement: Private notification reads and read state
Authenticated users SHALL be able to list only their own notifications, obtain an unread count, mark one read, and mark all eligible notifications through a supplied snapshot cursor read. Listing SHALL use descending creation time and ID with bounded pagination. Read mutations SHALL require current-site authentication, same-origin validation, and CSRF. Reads and unread counts SHALL recheck target visibility, blocks, reception, and membership; inaccessible targets SHALL contribute neither content nor counts. All responses SHALL be no-store and exclude private account fields.

#### Scenario: Membership revoked after delivery
- **WHEN** a recipient loses access to the notified private post
- **THEN** notification listing and unread counts omit that notification without leaking its title or author

#### Scenario: Mark all with concurrent arrival
- **WHEN** a client marks all read through a cursor while a newer notification arrives
- **THEN** only eligible notifications at or before that cursor become read

### Requirement: Moderation and report notifications
Resolved or rejected reports, community bans, and site bans SHALL create durable notifications for eligible local recipients. A report resolution SHALL notify the local reporter; a ban SHALL notify the affected local account when it remains eligible to receive notifications. Self-actions SHALL NOT notify. Notification kinds SHALL be distinct from reply, like, and mention, and SHALL identify the target by kind and identifier even when no post is involved. Replayed or retried events SHALL NOT duplicate a logical notification. Notification rows whose target becomes inaccessible SHALL contribute neither content nor unread counts.

#### Scenario: Reporter notified
- **WHEN** a local reporter's open report is resolved
- **THEN** the reporter receives one moderation notification with the resolution state and target identity

#### Scenario: Duplicate resolution delivery
- **WHEN** a resolution event is retried by a worker
- **THEN** the reporter still has at most one notification for that event

#### Scenario: Inaccessible target
- **WHEN** a report target becomes unreadable to the reporter
- **THEN** the notification listing and unread count omit it without leaking target content

### Requirement: Block-aware notification eligibility
Personal blocks SHALL suppress notifications from blocked persons and notifications about blocked communities or blocked instances. A notification created before a block SHALL disappear from the list and unread count while the block is active. Unblocking SHALL NOT recreate retired events. Existing reply, like, and mention eligibility SHALL continue to recheck current access, membership, reception, and site policy.

#### Scenario: Block after notification
- **WHEN** an account blocks a person after receiving that person's reply notification
- **THEN** the notification is excluded from the next list and unread count

#### Scenario: Unblock does not resurrect
- **WHEN** the account later unblocks the person
- **THEN** the old notification remains retired and only a new eligible event may notify again
