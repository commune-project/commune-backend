-- Explicit per-peer capability record. A peer without a verified protected-read
-- profile is not a valid destination for member-readable content.
CREATE TABLE peer_capabilities (
    domain text PRIMARY KEY CHECK (domain = lower(domain) AND length(domain) > 0),
    protected_reads boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now()
);
