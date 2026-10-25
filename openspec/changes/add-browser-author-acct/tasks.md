## 1. Schema, configuration, and storage

- [ ] 1.1 Add `014_actor_handles.sql` with `actors.acct` and `actor_handle_jobs`, register it in the migration catalog, and verify migration application plus default empty handles on existing rows.
- [ ] 1.2 Add `participation_workers.actor_workers` with a default of 1 and the existing 1–32 bounds; verify defaults, invalid values, and backward-compatible configuration loading.
- [ ] 1.3 Implement job enqueue, claim, lease, retry, terminal-state, and suppression storage functions; verify idempotent enqueue, expired-lease reclamation, attempt limits, and site-scoped uniqueness in PostgreSQL tests.

## 2. Enqueue and remote handle resolution

- [ ] 2.1 Call `QueueActorHandleResolution` from accepted remote post reception; verify remote Person authors enqueue once, local/Group/existing-handle authors do not, and replay creates no duplicate job.
- [ ] 2.2 Add an Accept-aware bounded fetch variant and keep existing `Fetch` callers unchanged; verify ActivityPub requests retain their current header while WebFinger requests send `application/jrd+json`.
- [ ] 2.3 Implement Actor document plus WebFinger verification; verify matching `id`, `type`, `preferredUsername`, `subject`, and single ActivityPub `self` link persist the handle, while mismatches, duplicate keys, unresolved custom domains, and unsafe destinations do not.
- [ ] 2.4 Implement the actor-handle worker batch with success, retry, terminal failure, and site-block suppression classification; verify one failed job does not block others and exhausted attempts leave `acct` empty.
- [ ] 2.5 Bootstrap blank remote profile display names from a verified Actor document's ActivityPub `name`; verify blank profiles fill, non-empty and local profiles remain unchanged, and `profiles.updated_at` is not advanced on conflict.

## 3. Browser author projection

- [ ] 3.1 Extend `PostRichState` and the existing batched post enrichment query with account username, site origin, `actors.acct`, and profile display name; verify query count remains page-size independent.
- [ ] 3.2 Add `AuthorOutput`, populate it in `BrowserPosts`, and retain `author_actor_uri`; verify lists, detail, replies, search, publication, editing, and import responses all expose `{acct, display_name}`.
- [ ] 3.3 Add browser HTTP tests for local authors, resolved remote authors, unresolved remote authors, blank display names, and unknown handles; verify reads make no WebFinger or Actor fetch and return empty strings rather than inferred values.

## 4. Frontend

- [ ] 4.1 Extend the Elm `Post` decoder with nested `author` and fall back to `author_actor_uri` when the object is absent; verify decoder tests for new, missing, and empty-field payloads.
- [ ] 4.2 Update post author rendering to prefer display name plus `@acct`, then handle-only, then Actor URI; verify Elm and browser tests cover each fallback and keep author text isolated with `bdi`.

## 5. Runtime, documentation, and acceptance

- [ ] 5.1 Integrate `actor_handles` into worker startup, polling, batch limits, and graceful shutdown; verify cancellation, lease recovery, and multi-worker exclusion tests.
- [ ] 5.2 Update browser API, configuration, federation, persistence, and frontend documentation with the `author` contract, worker defaults, migration 014, and unresolved-handle behavior; verify examples match HTTP responses.
- [ ] 5.3 Regenerate MyGO output through the existing package order, run bounded build/test/test-postgres suites, and run `openspec validate add-browser-author-acct --strict`; verify no generated file was edited manually and all acceptance evidence is recorded.
