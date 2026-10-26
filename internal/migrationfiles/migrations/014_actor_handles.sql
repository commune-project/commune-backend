ALTER TABLE actors ADD COLUMN acct text NOT NULL DEFAULT '';
ALTER TABLE actors ADD CONSTRAINT actors_acct_shape
    CHECK (acct = '' OR (position('@' IN acct) > 1 AND acct NOT LIKE '@%'));

CREATE TABLE actor_handle_jobs (
    site_id text NOT NULL REFERENCES sites(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    state text NOT NULL DEFAULT 'pending'
        CHECK (state IN ('pending','leased','done','failed','suppressed')),
    attempts int NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at timestamptz NOT NULL DEFAULT now(),
    lease_token text,
    lease_until timestamptz,
    error_code text,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, actor_uri)
);

CREATE INDEX actor_handle_jobs_ready
    ON actor_handle_jobs (available_at, site_id, actor_uri)
    WHERE state IN ('pending','leased');
