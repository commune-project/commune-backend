CREATE TABLE pending_registrations (
    id text PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    username text NOT NULL CHECK (username ~ '^[a-z0-9_][a-z0-9_-]{0,63}$'),
    email text NOT NULL CHECK (email = lower(email) AND position('@' IN email) > 1),
    token_hash bytea NOT NULL CHECK (octet_length(token_hash)=32),
    generation bigint NOT NULL DEFAULT 1 CHECK (generation > 0),
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL CHECK (expires_at > created_at),
    UNIQUE(site_id,email),
    UNIQUE(site_id,username),
    UNIQUE(site_id,token_hash)
);
CREATE INDEX pending_registration_expiry ON pending_registrations(expires_at);

CREATE TABLE verification_mail_jobs (
    id text PRIMARY KEY,
    registration_id text NOT NULL REFERENCES pending_registrations(id) ON DELETE CASCADE,
    generation bigint NOT NULL CHECK (generation>0),
    encrypted_payload bytea NOT NULL,
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
    available_at timestamptz NOT NULL,
    lease_token text,
    lease_until timestamptz,
    state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','leased','sent','failed')),
    CHECK ((lease_token IS NULL)=(lease_until IS NULL)),
    UNIQUE(registration_id,generation)
);
CREATE INDEX verification_mail_ready ON verification_mail_jobs(available_at) WHERE state IN ('pending','leased');

CREATE TABLE registration_rate_limits (
    site_id text NOT NULL REFERENCES sites(id),
    dimension text NOT NULL CHECK(dimension IN ('ip','email')),
    subject_hash bytea NOT NULL CHECK(octet_length(subject_hash)=32),
    window_start timestamptz NOT NULL,
    attempts integer NOT NULL CHECK(attempts>0),
    PRIMARY KEY(site_id,dimension,subject_hash,window_start)
);
