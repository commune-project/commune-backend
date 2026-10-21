-- Source triggers run within the accepting mutation transaction. Projection is
-- separately restartable; occurrences are never inferred from worker time.
CREATE TABLE post_mentions (
    id text PRIMARY KEY,
    post_id text NOT NULL REFERENCES posts(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    active boolean NOT NULL DEFAULT true,
    source_start integer NOT NULL DEFAULT 0 CHECK (source_start>=0),
    source_end integer NOT NULL DEFAULT 0 CHECK (source_end>=source_start),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX post_mentions_active ON post_mentions(post_id,actor_uri) WHERE active;
CREATE TABLE notification_events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    kind text NOT NULL CHECK (kind IN ('reply','like','mention')),
    occurrence text NOT NULL,
    post_id text NOT NULL REFERENCES posts(id),
    actor_uri text NOT NULL REFERENCES actors(uri),
    recipient_uri text NOT NULL REFERENCES actors(uri),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    retired_at timestamptz,
    projected boolean NOT NULL DEFAULT false,
    UNIQUE(kind, occurrence)
);
CREATE TABLE notifications (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id bigint NOT NULL REFERENCES notification_events(id),
    site_id text NOT NULL,
    account_id bigint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    read_at timestamptz,
    FOREIGN KEY(site_id, account_id) REFERENCES accounts(site_id,id),
    UNIQUE(event_id,account_id)
);
CREATE INDEX notification_pending ON notification_events(id) WHERE NOT projected;
CREATE INDEX notification_active_mentions ON notification_events(post_id,recipient_uri)
    INCLUDE (occurrence) WHERE kind='mention' AND retired_at IS NULL;
CREATE INDEX notification_recipient_page ON notifications(site_id,account_id,created_at DESC,id DESC);
ALTER TABLE reactions ADD COLUMN notification_generation bigint NOT NULL DEFAULT 1;

-- Current access is evaluated both at projection and on every read. This is
-- intentionally independent of delayed retirement/cleanup workers.
CREATE FUNCTION commune_notification_eligible(account bigint, post text, author text)
RETURNS boolean LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM accounts a JOIN posts p ON p.id=post
    JOIN communities c ON c.id=p.community_id
    JOIN site_posts sp ON sp.post_id=p.id AND sp.site_id=a.site_id
    WHERE a.id=account AND NOT a.disabled AND a.actor_uri<>author
    AND p.deleted_at IS NULL AND sp.hidden_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM accounts dead WHERE dead.actor_uri=author AND dead.disabled)
    AND NOT EXISTS(SELECT 1 FROM site_actor_blocks b WHERE b.site_id=a.site_id AND b.actor_uri IN (a.actor_uri,author,p.author_actor_uri))
    AND NOT EXISTS(SELECT 1 FROM site_domain_blocks b WHERE b.site_id=a.site_id AND b.domain IN
        (lower(split_part(split_part(a.actor_uri,'/',3),':',1)),lower(split_part(split_part(author,'/',3),':',1)),lower(split_part(split_part(p.author_actor_uri,'/',3),':',1))))
    AND NOT EXISTS(SELECT 1 FROM collection_memberships cm WHERE cm.post_id=p.id AND cm.community_id=p.community_id AND cm.state IN ('removed','rejected'))
    AND (p.parent_id IS NULL OR EXISTS (
        SELECT 1 FROM posts parent JOIN site_posts ps ON ps.post_id=parent.id AND ps.site_id=a.site_id
        WHERE parent.id=p.parent_id AND parent.community_id=p.community_id AND parent.deleted_at IS NULL AND ps.hidden_at IS NULL
        AND NOT EXISTS(SELECT 1 FROM collection_memberships cm WHERE cm.post_id=parent.id AND cm.community_id=parent.community_id AND cm.state IN ('removed','rejected'))))
    AND (
        (c.federation_mode IN ('federated','local_only') AND c.read_policy IN ('eligible_users','members')
         AND c.post_policy IN ('eligible_users','members') AND (c.read_policy<>'members' OR c.post_policy='members')
         AND (c.federation_mode='federated' OR c.host_site_id=a.site_id)
         AND (c.read_policy='eligible_users' OR EXISTS(SELECT 1 FROM community_members m WHERE m.community_id=c.id AND m.actor_uri=a.actor_uri AND m.revoked_at IS NULL)))
        OR (c.host_site_id=a.site_id AND (
            EXISTS(SELECT 1 FROM site_roles r WHERE r.site_id=a.site_id AND r.account_id=a.id)
            OR EXISTS(SELECT 1 FROM deployment_roles r WHERE r.account_id=a.id)
            OR (c.creator_actor_uri=a.actor_uri OR EXISTS(SELECT 1 FROM moderators m WHERE m.community_id=c.id AND m.actor_uri=a.actor_uri AND m.revoked_at IS NULL))))
    )
);
$$;

CREATE FUNCTION commune_notification_reaction_generation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.undone_at IS NOT NULL AND NEW.undone_at IS NULL THEN
        NEW.notification_generation := OLD.notification_generation + 1;
    ELSE
        NEW.notification_generation := OLD.notification_generation;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER notification_generation BEFORE UPDATE ON reactions
    FOR EACH ROW EXECUTE FUNCTION commune_notification_reaction_generation();

CREATE FUNCTION commune_notification_source() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE recipient text; occurrence_key text;
BEGIN
    IF TG_TABLE_NAME='posts' THEN
        IF TG_OP='INSERT' AND NEW.parent_id IS NOT NULL AND NEW.deleted_at IS NULL THEN
            SELECT author_actor_uri INTO recipient FROM posts WHERE id=NEW.parent_id AND deleted_at IS NULL;
            IF recipient IS NOT NULL AND recipient<>NEW.author_actor_uri THEN
                INSERT INTO notification_events(kind,occurrence,post_id,actor_uri,recipient_uri)
                VALUES('reply',NEW.id,NEW.id,NEW.author_actor_uri,recipient) ON CONFLICT DO NOTHING;
            END IF;
        END IF;
        IF NEW.deleted_at IS NOT NULL THEN
            UPDATE notification_events SET retired_at=coalesce(retired_at,clock_timestamp())
            WHERE post_id=NEW.id OR (kind='reply' AND post_id IN (SELECT id FROM posts WHERE parent_id=NEW.id));
        END IF;
    ELSIF TG_TABLE_NAME='reactions' THEN
        occurrence_key := json_build_array(NEW.post_id,NEW.actor_uri,NEW.notification_generation)::text;
        IF NEW.undone_at IS NULL THEN
            SELECT author_actor_uri INTO recipient FROM posts WHERE id=NEW.post_id AND deleted_at IS NULL;
            IF recipient IS NOT NULL AND recipient<>NEW.actor_uri THEN
                INSERT INTO notification_events(kind,occurrence,post_id,actor_uri,recipient_uri)
                VALUES('like',occurrence_key,NEW.post_id,NEW.actor_uri,recipient) ON CONFLICT DO NOTHING;
            END IF;
        ELSE
            UPDATE notification_events SET retired_at=coalesce(retired_at,clock_timestamp())
            WHERE kind='like' AND occurrence=occurrence_key;
        END IF;
    ELSE
        IF TG_OP='DELETE' THEN
            UPDATE notification_events SET retired_at=coalesce(retired_at,clock_timestamp())
            WHERE kind='mention' AND occurrence=OLD.id;
            RETURN OLD;
        END IF;
        IF NEW.active THEN
            SELECT author_actor_uri INTO recipient FROM posts WHERE id=NEW.post_id AND deleted_at IS NULL;
            IF recipient IS NOT NULL AND recipient<>NEW.actor_uri THEN
                INSERT INTO notification_events(kind,occurrence,post_id,actor_uri,recipient_uri)
                VALUES('mention',NEW.id,NEW.post_id,recipient,NEW.actor_uri) ON CONFLICT DO NOTHING;
            END IF;
        ELSE
            UPDATE notification_events SET retired_at=coalesce(retired_at,clock_timestamp())
            WHERE kind='mention' AND occurrence=NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER notification_post AFTER INSERT OR UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION commune_notification_source();
CREATE TRIGGER notification_reaction AFTER INSERT OR UPDATE ON reactions
    FOR EACH ROW EXECUTE FUNCTION commune_notification_source();
CREATE TRIGGER notification_mention AFTER INSERT OR UPDATE OR DELETE ON post_mentions
    FOR EACH ROW EXECUTE FUNCTION commune_notification_source();

CREATE FUNCTION commune_notification_mention_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.id<>OLD.id OR NEW.post_id<>OLD.post_id OR NEW.actor_uri<>OLD.actor_uri
       OR (NOT OLD.active AND NEW.active) THEN
        RAISE EXCEPTION 'mention reintroduction requires a fresh occurrence' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER notification_mention_identity BEFORE UPDATE ON post_mentions
    FOR EACH ROW EXECUTE FUNCTION commune_notification_mention_identity();
