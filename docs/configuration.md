# Configuration and routing

Build with `make build`, then run:

```sh
/tmp/commune-mygo-build/commune check-config config/example.json
```

This validates configuration without connecting to a database or starting an
HTTP listener. Serving, provisioning and migrations remain separate pending
commands. `config/example.json` is a schema example, not a live deployment.

The JSON contains sites, a PostgreSQL connection URL, trusted proxy CIDRs and
explicit runtime limits. Protect configuration files containing credentials.
Errors do not echo the database URL or malformed JSON contents. Each site has
a unique lowercase ASCII id, a canonical HTTPS origin, and optional routing
aliases expressed as authorities (host with optional port, without scheme).

Origins have no credentials, non-root path, query or fragment. Hostnames use
ASCII IDNA form. DNS case, one trailing DNS dot and HTTPS port 443 normalize
away; IPv6 literals normalize through net/netip. Non-default ports are retained.
Canonical origins and aliases share one uniqueness namespace, including
duplicates within the same site's aliases. Aliases route to the canonical
identity; they do not produce alternate object identities.

All timeout and limit fields are required. Read/write/shutdown timeouts are
1–300 seconds, idle timeout is 1–3600 seconds, request body size is
1024–16777216 bytes, maximum page size is 1–1000, and worker count is 1–128.
The listen address requires an explicit host and port. The database URL must
use postgres or postgresql and identify a valid host/port and a database path.

`ResolveSite` accepts the HTTP Host, direct TCP peer address and
X-Forwarded-Host. Only a direct peer inside a configured trusted CIDR can
replace Host with X-Forwarded-Host. Trusted proxies must overwrite the header,
not append to it; comma-separated chains are rejected. Invalid TCP peers and
untrusted clients cannot influence routing through forwarded headers. An
unknown authority has no default site. RFC Forwarded is not used for routing.

`CanonicalURI` builds supported resource identifiers from the configured
origin and an escaped single path segment. Incoming host/forwarded headers
never determine canonical identifiers. These helpers will be used at the HTTP
boundary; the server itself is not yet implemented.

Run `make test` for configuration rejection, secret-free error, IPv6, alias,
unknown-host and trusted/untrusted proxy regression cases. Result constructors
on early-return paths use explicit generic arguments to preserve their concrete
Go runtime variants with the current compiler.

## Participation configuration

Existing configuration files remain valid. New numeric fields omitted or set to
zero use defaults; negative values and values outside the bounds below fail.
Existing runtime/federation requirements are unchanged. All JSON keys use snake_case.
`Validate(Input)` applies `ParticipationDefaults(Input)`, resolves secrets using
`ResolveParticipationSecrets(Input) -> Result[Input, String]`, and calls
`ValidateParticipation(Input)` before returning the populated `Config`.
Direct callers of `ValidateParticipation` must apply defaults and resolve secrets first.

Each site has `registration_enabled` (default false). Initial registration takes
only username/email; confirmation takes the token and final password. Enabling
any site requires `registration.outbox_secret`, standard base64 encoding exactly
32 random bytes, and `smtp.host` plus a valid `smtp.from` mailbox. Alternatively,
set `registration.outbox_secret_env` to the name of an environment variable
containing that base64 key; `Validate`/`Load` resolve it into the returned
`Config.Registration.OutboxSecret`. Both sources together, an absent/empty
environment value, or a malformed/non-32-byte key are rejected. Both source
fields default empty. For example, set `outbox_secret_env` to
`COMMUNE_OUTBOX_KEY` and inject that variable through your service manager.
Keep the key
outside the database and protect the configuration file. Errors never echo keys
or SMTP credentials. SMTP username/password must be supplied together.
`smtp.tls_mode` defaults to `starttls`; `tls` means implicit TLS. `test` is an
explicit test transport mode and rejects credentials. Production transports must
protect authentication with TLS; config validation makes no network connections.

`media.enabled` and `participation_workers.enabled` default false. `media.root`
defaults empty; enabling media requires a clean absolute non-root path without
NULs or traversal segments. A supplied root is validated even when disabled.
Provision a persistent directory outside any directly served web root. Validation
does not create directories or probe disk/network; root-relative symlink-safe
opens belong to the storage implementation. Keep local-source, temporary-upload,
preview, and remote-private-cache namespaces separate. Back up authoritative
local files with the database; remote-private cache bytes are disposable.
Remote public media must never be fetched or cached by backend workers.

| JSON section.field | Default | Inclusive bounds |
| --- | ---: | --- |
| registration.token_ttl_seconds | 86400 | 60–604800 |
| registration.rate_window_seconds | 3600 | 60–86400 |
| registration.ip_limit | 20 | 1–10000 |
| registration.email_limit | 3 | 1–100 |
| smtp.port | 587 | 1–65535 |
| smtp.timeout_seconds | 10 | 1–60 |
| media.max_file_bytes | 26214400 | 1024–1073741824 |
| media.max_image_bytes | 10485760 | 1024–1073741824 |
| media.max_image_pixels | 20000000 | 1–100000000 |
| media.max_image_dimension | 16384 | 1–65536 |
| media.preview_dimension | 1024 | 1–4096 |
| media.account_quota_bytes | 1073741824 | 1024–1099511627776 |
| media.site_quota_bytes | 10737418240 | 1024–1099511627776 |
| media.temporary_retention_seconds | 86400 | 60–2592000 |
| media.private_cache_retention_seconds | 604800 | 60–31536000 |
| media.cleanup_interval_seconds | 3600 | 1–86400 |
| rendering.max_source_bytes | 1048576 | 1–16777216 |
| rendering.max_display_name_length | 100 | 1–1000 |
| rendering.max_biography_length | 5000 | 1–100000 |
| rendering.max_mentions | 20 | 1–100 |
| rendering.max_remote_discoveries | 10 | 1–100 |
| rendering.mention_timeout_seconds | 10 | 1–60 |
| participation_workers.mail_workers | 1 | 1–32 |
| participation_workers.notification_workers | 1 | 1–32 |
| participation_workers.media_workers | 1 | 1–32 |
| participation_workers.actor_workers | 1 | 1–32 |
| participation_workers.batch_size | 100 | 1–1000 |
| participation_workers.poll_interval_seconds | 5 | 1–300 |
| participation_workers.lease_seconds | 60 | 1–3600 |
| participation_workers.max_attempts | 8 | 1–100 |
| participation_workers.retry_base_seconds | 30 | 1–3600 |
| participation_workers.retry_max_seconds | 3600 | 1–86400 |

Byte limits are bytes; retention, lease, retry, timeout, poll, and rate-window
values are seconds. Image pixels bound total decoded pixels, dimensions bound
each axis. Profile lengths and mention counts bound rendered input handling.
Rate limits are per site, keyed separately by trusted client IP and normalized
email. Worker counts apply per process; leases coordinate competing processes.
Lease duration must exceed the SMTP timeout; retry base must not exceed maximum.
Image bytes must not exceed file bytes, account quota must cover a file, site
quota must cover an account, and preview dimension must not exceed image dimension.
The operational defaults are 25 MiB/file, 10 MiB/image, 20 megapixels, 1 GiB/account,
10 GiB/site, 24-hour temporary retention, 7-day private-cache retention and hourly
cleanup. Cache retention begins at successful fetch and is never renewed by reads.
Enable `participation_workers.enabled` to run mail, notification, media cleanup,
orphan reconciliation, actor-handle resolution, and federation delivery loops.
`runtime.workers` sets the number of federation delivery workers per process.
All loops stop with the server lifetime; database leases coordinate concurrent
processes. Actor-handle workers perform bounded, site-block-aware WebFinger
resolution for remote Person authors; browser reads never perform this lookup.
Cleanup never prefetches remote public media.
