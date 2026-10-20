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
