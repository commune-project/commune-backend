## ADDED Requirements

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
