## ADDED Requirements

### Requirement: Browser post author projection

Every successful browser post representation, including topic and reply lists, post detail, search results, publication, editing, and import, SHALL retain `author_actor_uri` and add an `author` object with string fields `acct` and `display_name`. `acct` SHALL be the verified local or remote handle in `username@domain` form without a leading `@`, or the empty string when unknown. `display_name` SHALL be the ActivityPub `name` value currently stored for the author, or the empty string when unset. The server SHALL NOT derive `acct` from Actor URI path segments and SHALL NOT perform a synchronous remote lookup while producing a browser response. `author_actor_uri` SHALL remain the authoritative identity for permissions, editing, and fallback display. Both strings SHALL always be present and SHALL NOT be null.

#### Scenario: Local author projection
- **WHEN** a browser reads a post authored by local account `alice` with display name `Alice`
- **THEN** `author_actor_uri` remains the account Actor URI and `author` is `{acct: "alice@forum.example", display_name: "Alice"}`

#### Scenario: Remote author with resolved handle
- **WHEN** a remote Person author has a verified stored handle and display name
- **THEN** every list, detail, search, and mutation response exposes the same `acct` and `display_name`

#### Scenario: Unresolved remote author
- **WHEN** a remote Person author has no verified handle or display name yet
- **THEN** `author` is `{acct: "", display_name: ""}` and clients fall back to `author_actor_uri`

#### Scenario: Display name without handle
- **WHEN** an author has a display name but no verified handle
- **THEN** `display_name` is returned and `acct` remains empty rather than being guessed

#### Scenario: No synchronous federation during read
- **WHEN** a browser lists posts whose authors have unresolved handles
- **THEN** the response is produced from stored data without a WebFinger or Actor fetch and without an additional per-post lookup that grows with page size
