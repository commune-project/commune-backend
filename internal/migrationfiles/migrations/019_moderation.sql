CREATE TABLE reports (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    reporter_account_id bigint NOT NULL,
    target_kind text NOT NULL CHECK (target_kind IN ('post','community','person')),
    target_id text NOT NULL,
    community_id text REFERENCES communities(id),
    reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 1000),
    state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved','rejected')),
    resolver_account_id bigint,
    resolution_note text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    FOREIGN KEY (site_id, reporter_account_id) REFERENCES accounts(site_id, id)
);
CREATE UNIQUE INDEX reports_open_unique ON reports(site_id, reporter_account_id, target_kind, target_id) WHERE state='open';
CREATE INDEX reports_scope ON reports(site_id, state, community_id, created_at DESC, id DESC);

CREATE TABLE moderation_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    community_id text REFERENCES communities(id),
    actor_account_id bigint NOT NULL,
    actor_actor_uri text NOT NULL REFERENCES actors(uri),
    action text NOT NULL,
    target_kind text NOT NULL,
    target_id text NOT NULL,
    reason text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (site_id, actor_account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX moderation_log_scope ON moderation_log(site_id, community_id, created_at DESC, id DESC);

CREATE FUNCTION commune_moderation_log_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'moderation log entries are append-only' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER moderation_log_immutable BEFORE UPDATE OR DELETE ON moderation_log
    FOR EACH ROW EXECUTE FUNCTION commune_moderation_log_immutable();

CREATE TABLE community_bans (
    community_id text NOT NULL REFERENCES communities(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    banned_by_actor_uri text NOT NULL REFERENCES actors(uri),
    reason text NOT NULL DEFAULT '',
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (community_id, actor_uri)
);
CREATE INDEX community_bans_active ON community_bans(community_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE site_bans (
    site_id text NOT NULL REFERENCES sites(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    banned_by_actor_uri text NOT NULL REFERENCES actors(uri),
    reason text NOT NULL DEFAULT '',
    expires_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, actor_uri)
);
CREATE INDEX site_bans_active ON site_bans(site_id, expires_at) WHERE revoked_at IS NULL;
