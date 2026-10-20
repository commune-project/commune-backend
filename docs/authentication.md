# Site-local authentication

Provision sites after explicit migration, then create an ordinary account:

```sh
read -rs COMMUNE_ACCOUNT_PASSWORD
export COMMUNE_ACCOUNT_PASSWORD
/tmp/commune-mygo-build/commune provision-account config/example.json site-a alice alice@example.org
unset COMMUNE_ACCOUNT_PASSWORD
```

The optional final argument is an email address. Accounts receive no administrator
grant. Creation fails for an existing username or email on that site; it never
replaces credentials. Passwords must contain 12–72 bytes and are hashed with
bcrypt. Usernames are lowercase; email login is trimmed and case insensitive.
The same username and email may belong to independent accounts at other sites.
There is no public registration endpoint yet.

All requests select the configured site through its validated HTTP authority.
Use HTTPS in the browser, including when TLS terminates at a configured proxy.

| Endpoint | Method | Requirements | Success |
| --- | --- | --- | --- |
| `/api/v1/auth/login` | POST | Same-origin `Origin`; JSON `login` and `password` | 200 identity and two cookies |
| `/api/v1/auth/session` | GET | Valid session cookie | 200 current identity |
| `/api/v1/auth/logout` | POST | Valid session, same-origin `Origin`, `X-CSRF-Token` | 204 and expired cookies |

Login accepts a username or email. JSON example:

```json
{"login":"alice@example.org","password":"your-account-password"}
```

The identity response contains `site_id`, `account_id`, `actor_uri`, and `username`.
It excludes passwords and password hashes. Unknown fields, extra JSON values,
malformed input and bodies exceeding the configured limit are rejected with 400.
Invalid credentials or sessions return 401; origin/CSRF failures return 403;
unsupported methods return 405; unavailable authentication storage returns 503.

Sessions expire after 24 hours. PostgreSQL stores only SHA-256 hashes of the
independent session and CSRF secrets. Both cookies use the `__Host-` prefix,
`Secure`, `SameSite=Strict`, `Path=/`, and no Domain attribute. The session cookie
is HttpOnly. The CSRF cookie is readable by the site's browser code so it can
copy the value into `X-CSRF-Token` for logout. Responses use `Cache-Control:
no-store`. A valid session from another site cannot authenticate the request.
Logout revokes the database session, and disabling an account immediately
invalidates its sessions. No authorization state is cached in session tokens.

`make test-postgres` exercises independent accounts, email login, disabled
accounts, expiry/revocation, cross-site cookie replay, login origin validation,
CSRF rejection, and HTTP logout using an isolated real PostgreSQL database.
