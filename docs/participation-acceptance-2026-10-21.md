# Participation process acceptance: 2026-10-21

Tasks 9.3 and 9.4 passed using real HTTP requests, two independently running
Commune executables, two isolated PostgreSQL databases, and separate media roots.
Deployment A also hosts site C, selected by a different HTTPS authority, for
same-deployment site-isolation checks. No existing developer database is used.

## Reproduce

```sh
ulimit -v 8000000
export GOCACHE=/tmp/commune-participation-gocache
export GOMODCACHE=/tmp/commune-mygo-modcache
timeout 420 make build test test-postgres
timeout 240 python3 scripts/participation-acceptance.py --report /tmp/commune-participation-acceptance-report.json
timeout 90 python3 scripts/participation-acceptance.py --local-only --report /tmp/commune-local-acceptance-report.json
openspec validate add-forum-participation-and-media --strict
git diff --check
```

Both acceptance commands exited 0. The full run reported 12 passing checkpoints;
the separately strengthened local matrix reported 6. Full regression tests also
passed; PostgreSQL server/storage package times were 12.402/14.114 seconds.
The full exchange includes a real wait for the configured minimum 60-second
private-cache retention and the periodic cleaner; timestamps are not rewritten.

The script requires PostgreSQL tools, OpenSSL, Python, the built executable,
and permission to bind loopback sockets. It creates a temporary self-signed
certificate trusted only by its clients and child processes. TLS verification
remains enabled. A local SMTP receiver accepts only these generated test emails;
no external mailbox or federation instance is contacted. Private network access
is enabled only in the temporary test configurations.

## Version evidence

| Item | Observed value |
| --- | --- |
| Source base | `a239f321a5b0a62a67eeb323615886fe78a216f7`, with uncommitted participation changes |
| Executable SHA-256, both runs | `75dbd533d47ca7fa0f91382470ffc21fe01a4649776ffdf23ff09ccc41ff8f7e` |
| PostgreSQL | 18.6 |
| Go | go1.27.1 linux/amd64 |
| Python | 3.14.8 |
| Full-run Commune process IDs | 229520 and 229603 |

The report option records executable hash, tool versions, process IDs, checkpoints
and HTTP method/path/status traces without cookies, passwords, keys, verification
tokens or request bodies. Temporary test data is removed on normal exit. Set
`COMMUNE_ACCEPTANCE_KEEP=1` only for debugging; retained configurations contain
test secrets and must not be published.

## 9.3 matrix

| Contract | Process-level assertions |
| --- | --- |
| Verified registration | Real SMTP delivery, no account before redemption, final-password confirmation and login; independent same-name registration on A and C. |
| Profiles | Owner PATCH, image upload and avatar binding; C's independent profile and Actor identity. |
| Local media | Multipart image upload, post binding, validated PNG preview; member read succeeds, unrelated-site and revoked-member reads fail. |
| Rich content | Markdown sanitization, exact source retrieval, inline image, local mention and rich reply; existing like/edit/delete mutations remain usable. |
| Search | Chinese text finds the current readable post; C and revoked readers see no matching private post. |
| Notifications | Mention/like/reply projection via running workers, snapshot mark-all clears current unread state; unrelated-site and revoked readers see zero private counts. |
| Rich federation | Covered by the separate two-process matrix below, including recipient identity, public/private media, updates and local-only exclusion. |

An actual administrator HTTP read also produces a persisted audit event.

## 9.4 two-process matrix

- Person Follow and subsequent profile Update reach the peer; avatar replacement
  propagates as a direct source URL. Reverse-direction profile Update also lands.
- Public Group Announce transmits Markdown-derived HTML, structured attachment
  and canonical Mention; Update reconciles the received object. The reverse
  direction repeats Create/Update, attachment and mention exchange.
- At the public checkpoint, neither backend fetched any public attachment and
  the receiving database contained no private-cache row. Public avatar metadata
  likewise caused no backend media request.
- Private Group Announce verifies its canonical inner activity with an
  Actor-signed ActivityPub GET. An authorized browser request triggers a signed
  origin media fetch, validates the image and serves original/preview bytes.
- Cache hits leave expiry unchanged. After real expiry the periodic worker
  deletes both original and preview generations while retaining metadata; an
  authorized miss fetches again. The origin trace contains exactly two media
  GETs: the initial fetch and refetch. Preview/cache hits do not add origin reads.
- HTTP membership removal atomically queues a Group-signed, targeted revocation.
  The peer removes that Actor's membership and denies the known cached URL.
  The control message discloses no private post or remaining membership roster.
- A local-only topic creates no federated activity and no peer post.

The harness bootstraps known remote Actors from live actor GETs and creates
replica-community metadata plus the initial approved private membership. Where
no browser outbound-follow API exists, its protocol client persists its original
outbound Follow for canonical GET verification, then sends an actual signed POST.
It never seeds received posts, notifications, inbox receipts, delivery jobs or
cache bytes. Those results must be produced by the running services. This tests
the exchange after peer setup; it does not claim automated peer provisioning.

## Fixes found by acceptance

Person representations incorrectly declared a moderators collection as their
author, causing genuine profile Updates to be rejected. Signed canonical-activity
fetches used a media-only Accept header and received 404. Non-default HTTPS ports
were lost during remote-mention parsing. Browser membership removal had no
outbound revocation control message. These paths are now fixed and covered by
regression or process tests; targeted revocation preserves unrelated membership.

Task 9.5 remains intentionally unexecuted. No Lemmy, Mastodon or Misskey version
or interoperability result is claimed.
