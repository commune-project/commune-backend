## Purpose

Keep site-local users informed of replies, likes, and mentions with durable deduplicated records and permission-aware unread state.

## ADDED Requirements

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
