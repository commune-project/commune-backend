CREATE TABLE community_members (
    community_id text NOT NULL REFERENCES communities(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    approved_by text NOT NULL REFERENCES actors(uri),
    approved_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    PRIMARY KEY (community_id, actor_uri)
);
CREATE TABLE moderators (
    community_id text NOT NULL REFERENCES communities(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    assigned_by text NOT NULL REFERENCES actors(uri),
    assigned_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    PRIMARY KEY (community_id, actor_uri)
);
CREATE TABLE follows (
    community_id text NOT NULL REFERENCES communities(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    follow_uri text NOT NULL UNIQUE,
    state text NOT NULL CHECK (state IN ('pending','accepted','rejected','undone')),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (community_id, actor_uri)
);
CREATE TABLE site_posts (
    site_id text NOT NULL REFERENCES sites(id),
    post_id text NOT NULL REFERENCES posts(id),
    received_at timestamptz NOT NULL DEFAULT now(),
    hidden_at timestamptz,
    PRIMARY KEY (site_id, post_id)
);
CREATE TABLE post_audiences (
    post_id text NOT NULL REFERENCES posts(id),
    community_id text NOT NULL REFERENCES communities(id),
    declared_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, community_id)
);
CREATE TABLE post_contexts (
    post_id text NOT NULL REFERENCES posts(id),
    context_id text NOT NULL REFERENCES discussion_contexts(id),
    declared_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, context_id)
);
CREATE TABLE collection_memberships (
    post_id text NOT NULL REFERENCES posts(id),
    community_id text REFERENCES communities(id),
    context_id text REFERENCES discussion_contexts(id),
    authority_actor_uri text NOT NULL REFERENCES actors(uri),
    verification_method text NOT NULL CHECK (verification_method IN ('local_authority','signed_activity','canonical_collection')),
    evidence_uri text NOT NULL,
    state text NOT NULL CHECK (state IN ('pending','accepted','rejected','removed')),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK ((community_id IS NULL) != (context_id IS NULL))
);
CREATE UNIQUE INDEX community_inclusion ON collection_memberships(post_id, community_id) WHERE community_id IS NOT NULL;
CREATE UNIQUE INDEX context_inclusion ON collection_memberships(post_id, context_id) WHERE context_id IS NOT NULL;
CREATE TABLE reactions (
    post_id text NOT NULL REFERENCES posts(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    reaction_uri text UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    undone_at timestamptz,
    PRIMARY KEY (post_id, actor_uri)
);
CREATE TABLE activities (
    uri text PRIMARY KEY,
    actor_uri text NOT NULL REFERENCES actors(uri),
    kind text NOT NULL CHECK (kind IN ('Create','Update','Delete','Like','Undo','Follow','Accept','Reject','Announce','Add','Remove')),
    community_id text REFERENCES communities(id),
    post_id text REFERENCES posts(id),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE activity_payloads (
    activity_uri text PRIMARY KEY REFERENCES activities(uri),
    original_payload bytea NOT NULL,
    checksum bytea NOT NULL CHECK (octet_length(checksum)=32)
);
CREATE TABLE inbox_receipts (
    activity_uri text NOT NULL REFERENCES activity_payloads(activity_uri),
    site_id text NOT NULL REFERENCES sites(id),
    recipient_actor_uri text NOT NULL REFERENCES actors(uri),
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','processing','accepted','rejected')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
    lease_token text,
    lease_until timestamptz,
    error_code text,
    received_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (activity_uri, site_id, recipient_actor_uri),
    CHECK ((lease_token IS NULL) = (lease_until IS NULL))
);
CREATE TABLE delivery_jobs (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    activity_uri text NOT NULL REFERENCES activity_payloads(activity_uri),
    signing_actor_uri text NOT NULL REFERENCES actors(uri),
    recipient_actor_uri text NOT NULL REFERENCES actors(uri),
    target_inbox text NOT NULL CHECK (target_inbox LIKE 'https://%'),
    community_id text REFERENCES communities(id),
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','leased','delivered','suppressed','failed')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
    available_at timestamptz NOT NULL DEFAULT now(),
    lease_token text,
    lease_until timestamptz,
    error_code text,
    UNIQUE (activity_uri, signing_actor_uri, recipient_actor_uri, target_inbox),
    CHECK ((lease_token IS NULL) = (lease_until IS NULL)),
    CHECK ((state='leased') = (lease_token IS NOT NULL))
);
CREATE INDEX delivery_ready ON delivery_jobs(available_at,id) WHERE state IN ('pending','leased');
CREATE INDEX receipt_ready ON inbox_receipts(received_at) WHERE state IN ('pending','processing');

CREATE FUNCTION commune_relation_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c communities%ROWTYPE; p posts%ROWTYPE; target communities%ROWTYPE;
DECLARE context_row discussion_contexts%ROWTYPE;
BEGIN
    IF TG_TABLE_NAME IN ('community_members','moderators','follows') THEN
        SELECT * INTO c FROM communities WHERE id=NEW.community_id FOR SHARE;
        IF NOT EXISTS (SELECT 1 FROM actors WHERE uri=NEW.actor_uri AND kind='Person') THEN
            RAISE EXCEPTION 'community assignment requires a Person' USING ERRCODE='23514';
        END IF;
        IF c.federation_mode='local_only' THEN
            IF TG_TABLE_NAME='follows' OR NOT EXISTS
                (SELECT 1 FROM accounts WHERE actor_uri=NEW.actor_uri AND site_id=c.host_site_id) THEN
                RAISE EXCEPTION 'local community assignment cannot cross its site' USING ERRCODE='23514';
            END IF;
        END IF;
    ELSIF TG_TABLE_NAME IN ('site_posts','post_audiences','post_contexts','collection_memberships','reactions') THEN
        SELECT * INTO p FROM posts WHERE id=NEW.post_id FOR SHARE;
        SELECT * INTO c FROM communities WHERE id=p.community_id FOR SHARE;
        IF TG_TABLE_NAME='site_posts' THEN
            IF c.federation_mode='local_only' AND NEW.site_id IS DISTINCT FROM c.host_site_id THEN
                RAISE EXCEPTION 'local post cannot be received by another site' USING ERRCODE='23514';
            END IF;
        ELSIF TG_TABLE_NAME='reactions' THEN
            IF c.federation_mode='local_only' AND
                (NEW.reaction_uri IS NOT NULL OR NOT EXISTS
                    (SELECT 1 FROM accounts WHERE actor_uri=NEW.actor_uri AND site_id=c.host_site_id)) THEN
                RAISE EXCEPTION 'local reaction cannot be federated or cross its site' USING ERRCODE='23514';
            END IF;
        ELSE
            IF TG_TABLE_NAME='post_audiences' THEN
                SELECT * INTO target FROM communities WHERE id=NEW.community_id FOR SHARE;
            ELSIF TG_TABLE_NAME='post_contexts' OR NEW.context_id IS NOT NULL THEN
                SELECT * INTO context_row FROM discussion_contexts WHERE id=NEW.context_id FOR SHARE;
                IF context_row.community_id IS NOT NULL THEN
                    SELECT * INTO target FROM communities WHERE id=context_row.community_id FOR SHARE;
                END IF;
            ELSE
                SELECT * INTO target FROM communities WHERE id=NEW.community_id FOR SHARE;
            END IF;
            IF target.id IS DISTINCT FROM c.id AND
                (c.federation_mode='local_only' OR c.read_policy='members'
                 OR target.federation_mode='local_only' OR target.read_policy='members') THEN
                RAISE EXCEPTION 'relationship cannot cross a restricted boundary' USING ERRCODE='23514';
            END IF;
            IF TG_TABLE_NAME='collection_memberships' THEN
            IF NEW.state='accepted' AND
                ((NEW.community_id IS NOT NULL AND NEW.authority_actor_uri IS DISTINCT FROM coalesce(target.actor_uri,target.creator_actor_uri))
                 OR (NEW.context_id IS NOT NULL AND NEW.authority_actor_uri IS DISTINCT FROM context_row.authority_actor_uri)) THEN
                RAISE EXCEPTION 'inclusion authority must match its collection' USING ERRCODE='23514';
            END IF;
            END IF;
        END IF;
    ELSIF TG_TABLE_NAME='activities' THEN
        IF NEW.community_id IS NOT NULL THEN
            SELECT * INTO c FROM communities WHERE id=NEW.community_id FOR SHARE;
            IF c.federation_mode='local_only' THEN
                RAISE EXCEPTION 'local community cannot produce protocol activities' USING ERRCODE='23514';
            END IF;
        END IF;
        IF NEW.post_id IS NOT NULL THEN
            SELECT * INTO p FROM posts WHERE id=NEW.post_id FOR SHARE;
            IF p.federation_mode='local_only' THEN
                RAISE EXCEPTION 'local post cannot produce protocol activities' USING ERRCODE='23514';
            END IF;
        END IF;
    ELSIF TG_TABLE_NAME='inbox_receipts' THEN
        IF NOT EXISTS (SELECT 1 FROM actors WHERE uri=NEW.recipient_actor_uri AND local_site_id=NEW.site_id) THEN
            RAISE EXCEPTION 'receipt recipient must belong to its site' USING ERRCODE='23514';
        END IF;
    ELSE
        IF NEW.community_id IS NOT NULL AND EXISTS
            (SELECT 1 FROM communities WHERE id=NEW.community_id AND federation_mode='local_only') THEN
            RAISE EXCEPTION 'local community cannot have delivery jobs' USING ERRCODE='23514';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM actors WHERE uri=NEW.signing_actor_uri AND local_site_id IS NOT NULL AND private_key_pem IS NOT NULL) THEN
            RAISE EXCEPTION 'delivery signer needs a locally owned key' USING ERRCODE='23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
DO $$
DECLARE relation text;
BEGIN
    FOREACH relation IN ARRAY ARRAY['community_members','moderators','follows','site_posts',
        'post_audiences','post_contexts','collection_memberships','reactions','activities','inbox_receipts','delivery_jobs']
    LOOP
        EXECUTE format('CREATE TRIGGER relation_scope BEFORE INSERT OR UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION commune_relation_guard()',relation);
    END LOOP;
END $$;

CREATE FUNCTION commune_activity_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'accepted activity identity and payload are immutable' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER activity_immutable BEFORE UPDATE ON activities
    FOR EACH ROW EXECUTE FUNCTION commune_activity_immutable();
CREATE TRIGGER payload_immutable BEFORE UPDATE ON activity_payloads
    FOR EACH ROW EXECUTE FUNCTION commune_activity_immutable();
