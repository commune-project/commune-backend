CREATE TABLE password_reset_tokens (
    id text PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    token_hash bytea NOT NULL CHECK (octet_length(token_hash)=32),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    consumed_at timestamptz,
    UNIQUE (site_id, token_hash),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX password_reset_expiry ON password_reset_tokens(expires_at);

CREATE TABLE password_reset_mail_jobs (
    id text PRIMARY KEY,
    reset_id text NOT NULL UNIQUE REFERENCES password_reset_tokens(id) ON DELETE CASCADE,
    encrypted_payload bytea NOT NULL,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    available_at timestamptz NOT NULL,
    lease_token text,
    lease_until timestamptz,
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','leased','sent','failed')),
    CHECK ((lease_token IS NULL) = (lease_until IS NULL))
);
CREATE INDEX password_reset_mail_ready ON password_reset_mail_jobs(available_at) WHERE state IN ('pending','leased');

CREATE TABLE password_reset_rate_limits (
    site_id text NOT NULL REFERENCES sites(id),
    dimension text NOT NULL CHECK (dimension IN ('ip','email')),
    subject_hash bytea NOT NULL CHECK (octet_length(subject_hash)=32),
    window_start timestamptz NOT NULL,
    attempts integer NOT NULL CHECK (attempts > 0),
    PRIMARY KEY (site_id, dimension, subject_hash, window_start)
);
