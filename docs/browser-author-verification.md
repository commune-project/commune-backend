# Browser author handle verification

Implementation evidence for OpenSpec change `add-browser-author-acct`.

## Scope verified

- Browser post responses expose `author {acct, display_name}` and retain
  `author_actor_uri`.
- Local handles are derived from `accounts.username` and the author's canonical
  site authority.
- Remote handles are stored in `actors.acct` only after Actor document and
  WebFinger verification.
- Remote post reception enqueues one site-scoped `actor_handle_jobs` row;
  replay is idempotent.
- Actor-handle workers are leased, retried, bounded, site-block-aware, and
  restart-recoverable.
- Blank remote display names are bootstrapped from ActivityPub `name` without
  overwriting existing or local profiles.
- Browser reads use stored data only and do not perform Actor or WebFinger
  lookups.

## Commands and results

Run from the repository root unless noted.

Generation used the compiler commit pinned by
`.github/workflows/ci.yml` (`e19e0a6`) through a detached worktree, so the
committed generated format was preserved.

| Command | Result |
| --- | --- |
| `make generate MYGO_ROOT=<pinned MyGO checkout>` | Generated Go produced by the pinned MyGO compiler; no generated file was edited manually. |
| `go test ./...` | Passed; all packages, including `cmd/commune`, compiled. |
| `make test-postgres MYGO_ROOT=<pinned MyGO checkout>` | Passed against a temporary PostgreSQL cluster. |
| `ELM_HOME=/tmp/commune-elm-home npm test` (from `frontend/`) | 15 Node tests and 21 Elm tests passed. |
| `COMMUNE_TEST_URL=http://127.0.0.1:4174 npx playwright test tests-browser/forum.spec.js --reporter=line` | 27 browser tests passed. |
| `openspec validate add-browser-author-acct --strict` | Valid. |

## Focused coverage

- `TestPostgresActorHandleMigrationDefault`: migration 014 preserves existing
  actors with an empty handle and creates no jobs.
- `TestPostgresActorHandleJobsAndProfileBootstrap`: enqueue idempotency,
  site-scoped jobs, lease reclamation, retry/failure states, verified handle
  persistence, and blank-only profile bootstrap.
- `TestActorHandleResolutionValidation`: WebFinger/Actor identity chain and
  Accept headers; mismatched subjects, self links, Actor ids, Group documents,
  and empty `preferredUsername` are rejected.
- `TestPostgresActorHandleWorkerAndBrowserProjection`: local and remote author
  projection through both `BrowserPosts` and HTTP post routes; browser reads do
  not trigger remote fetches.
- `TestPostgresActorHandleWorkerOutcomes`: one batch isolates success, retry,
  terminal failure, and block suppression.
- `TestFetchAcceptVariants`: ActivityPub requests keep their Accept header and
  WebFinger requests send `application/jrd+json`.
- `DomainTest`: nested author decoding and fallback when the object is absent.
- Playwright forum fixture: display-name plus handle rendering.

## Limitations

- Remote handles for existing actors are not mass-backfilled. They resolve when
  the actor reappears in received content and a worker processes the job.
- Custom handle domains that cannot be resolved through the Actor authority
  remain empty rather than being guessed.
- No external-peer interoperability claim is made by these local tests.
