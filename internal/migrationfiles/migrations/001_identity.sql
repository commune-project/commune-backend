CREATE TABLE sites (
    id text PRIMARY KEY CHECK (id ~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$'),
    canonical_origin text NOT NULL UNIQUE CHECK (canonical_origin LIKE 'https://%'),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE site_authorities (
    authority text PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    UNIQUE (site_id, authority)
);

CREATE TABLE actors (
    uri text PRIMARY KEY,
    local_site_id text REFERENCES sites(id),
    kind text NOT NULL CHECK (kind IN ('Person', 'Group')),
    inbox_uri text,
    public_key_pem text,
    private_key_pem text,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (uri, local_site_id, kind),
    CHECK (local_site_id IS NOT NULL OR private_key_pem IS NULL)
);

CREATE TABLE accounts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    actor_uri text NOT NULL UNIQUE,
    actor_kind text NOT NULL DEFAULT 'Person' CHECK (actor_kind = 'Person'),
    username text NOT NULL CHECK (username ~ '^[a-z0-9_][a-z0-9_-]{0,63}$'),
    email text CHECK (email IS NULL OR (email = lower(email) AND position('@' IN email) > 1)),
    password_hash text NOT NULL CHECK (length(password_hash) > 0),
    disabled boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (site_id, id),
    UNIQUE (site_id, username),
    UNIQUE (site_id, email),
    FOREIGN KEY (actor_uri, site_id, actor_kind) REFERENCES actors(uri, local_site_id, kind)
);

CREATE TABLE sessions (
    token_hash bytea PRIMARY KEY CHECK (octet_length(token_hash) = 32),
    site_id text NOT NULL,
    account_id bigint NOT NULL,
    csrf_hash bytea NOT NULL CHECK (octet_length(csrf_hash) = 32),
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id),
    CHECK (expires_at > created_at)
);
CREATE INDEX sessions_account ON sessions(site_id, account_id);
CREATE INDEX sessions_expiry ON sessions(expires_at);

CREATE TABLE site_roles (
    site_id text NOT NULL,
    account_id bigint NOT NULL,
    role text NOT NULL CHECK (role = 'administrator'),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, account_id, role),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);

-- No deployment role is inferred from site_roles or assigned by a default.
CREATE TABLE deployment_roles (
    account_id bigint NOT NULL REFERENCES accounts(id),
    role text NOT NULL CHECK (role = 'superadministrator'),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, role)
);

CREATE TABLE audit_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    acting_actor_uri text NOT NULL REFERENCES actors(uri),
    scope_kind text NOT NULL CHECK (scope_kind IN ('deployment', 'site', 'community')),
    scope_id text NOT NULL,
    action text NOT NULL,
    target_id text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_scope ON audit_events(scope_kind, scope_id, id);

CREATE TABLE site_actor_blocks (
    site_id text NOT NULL REFERENCES sites(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    PRIMARY KEY (site_id, actor_uri)
);
CREATE TABLE site_domain_blocks (
    site_id text NOT NULL REFERENCES sites(id),
    domain text NOT NULL CHECK (domain = lower(domain) AND length(domain) > 0),
    PRIMARY KEY (site_id, domain)
);
