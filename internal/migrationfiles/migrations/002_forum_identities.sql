ALTER TABLE actors ADD CONSTRAINT actors_uri_kind_key UNIQUE (uri, kind);

CREATE TABLE communities (
    id text PRIMARY KEY,
    host_site_id text REFERENCES sites(id),
    actor_uri text UNIQUE,
    actor_kind text NOT NULL DEFAULT 'Group' CHECK (actor_kind = 'Group'),
    creator_actor_uri text NOT NULL,
    creator_kind text NOT NULL DEFAULT 'Person' CHECK (creator_kind = 'Person'),
    federation_mode text NOT NULL CHECK (federation_mode IN ('local_only','federated')),
    read_policy text NOT NULL CHECK (read_policy IN ('eligible_users','members')),
    post_policy text NOT NULL CHECK (post_policy IN ('eligible_users','members')),
    name text NOT NULL,
    title text NOT NULL,
    description text NOT NULL DEFAULT '',
    policy_version bigint NOT NULL DEFAULT 1 CHECK (policy_version > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (host_site_id, name),
    UNIQUE (id, federation_mode),
    FOREIGN KEY (actor_uri, actor_kind) REFERENCES actors(uri, kind),
    FOREIGN KEY (creator_actor_uri, creator_kind) REFERENCES actors(uri, kind),
    CHECK (read_policy != 'members' OR post_policy = 'members'),
    CHECK ((federation_mode = 'local_only' AND actor_uri IS NULL AND host_site_id IS NOT NULL)
        OR (federation_mode = 'federated' AND actor_uri IS NOT NULL))
);

CREATE TABLE posts (
    id text PRIMARY KEY,
    object_uri text UNIQUE,
    community_id text NOT NULL,
    federation_mode text NOT NULL,
    author_actor_uri text NOT NULL,
    author_kind text NOT NULL DEFAULT 'Person' CHECK (author_kind = 'Person'),
    object_type text NOT NULL CHECK (object_type IN ('Page','Note')),
    title text,
    body text NOT NULL DEFAULT '',
    parent_id text,
    authored_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    deleted_at timestamptz,
    UNIQUE (id, community_id),
    FOREIGN KEY (community_id, federation_mode) REFERENCES communities(id, federation_mode),
    FOREIGN KEY (author_actor_uri, author_kind) REFERENCES actors(uri, kind),
    FOREIGN KEY (parent_id, community_id) REFERENCES posts(id, community_id),
    CHECK (parent_id IS NULL OR parent_id != id),
    CHECK (updated_at >= authored_at),
    CHECK (deleted_at IS NULL OR body = ''),
    CHECK ((federation_mode = 'local_only' AND object_uri IS NULL)
        OR (federation_mode = 'federated' AND object_uri IS NOT NULL))
);
CREATE INDEX posts_community ON posts(community_id, authored_at, id);
CREATE INDEX posts_parent ON posts(parent_id);

CREATE TABLE discussion_contexts (
    id text PRIMARY KEY,
    context_uri text UNIQUE,
    community_id text REFERENCES communities(id),
    topic_id text REFERENCES posts(id),
    authority_actor_uri text REFERENCES actors(uri),
    collection_uri text,
    resolution_state text NOT NULL CHECK (resolution_state IN ('unresolved','non_collection','collection')),
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE FUNCTION commune_identity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c communities%ROWTYPE;
BEGIN
    IF TG_TABLE_NAME = 'communities' THEN
        IF TG_OP = 'UPDATE' AND
            (NEW.id,NEW.host_site_id,NEW.actor_uri,NEW.federation_mode)
            IS DISTINCT FROM (OLD.id,OLD.host_site_id,OLD.actor_uri,OLD.federation_mode) THEN
            RAISE EXCEPTION 'community identity and federation mode are immutable' USING ERRCODE = '23514';
        END IF;
        IF NEW.federation_mode = 'local_only' AND NOT EXISTS
            (SELECT 1 FROM accounts WHERE actor_uri=NEW.creator_actor_uri AND site_id=NEW.host_site_id) THEN
            RAISE EXCEPTION 'local community creator must belong to its site' USING ERRCODE = '23514';
        END IF;
        IF NEW.host_site_id IS NOT NULL AND NEW.actor_uri IS NOT NULL AND NOT EXISTS
            (SELECT 1 FROM actors WHERE uri=NEW.actor_uri AND local_site_id=NEW.host_site_id) THEN
            RAISE EXCEPTION 'hosted community actor must belong to its site' USING ERRCODE = '23514';
        END IF;
    ELSIF TG_TABLE_NAME = 'posts' THEN
        SELECT * INTO c FROM communities WHERE id=NEW.community_id FOR SHARE;
        IF c.federation_mode = 'local_only' AND NOT EXISTS
            (SELECT 1 FROM accounts WHERE actor_uri=NEW.author_actor_uri AND site_id=c.host_site_id) THEN
            RAISE EXCEPTION 'local post author must belong to its site' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'UPDATE' AND
            (NEW.id,NEW.object_uri,NEW.community_id,NEW.federation_mode,NEW.author_actor_uri,NEW.parent_id)
            IS DISTINCT FROM (OLD.id,OLD.object_uri,OLD.community_id,OLD.federation_mode,OLD.author_actor_uri,OLD.parent_id) THEN
            RAISE EXCEPTION 'post identity and ownership are immutable' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'UPDATE' AND OLD.deleted_at IS NOT NULL AND
            (NEW.deleted_at IS DISTINCT FROM OLD.deleted_at OR NEW.body != '') THEN
            RAISE EXCEPTION 'author tombstone cannot be resurrected' USING ERRCODE = '23514';
        END IF;
    ELSE
        IF NEW.community_id IS NOT NULL THEN
            SELECT * INTO c FROM communities WHERE id=NEW.community_id FOR SHARE;
            IF c.federation_mode = 'local_only' AND
                (NEW.context_uri IS NOT NULL OR NEW.collection_uri IS NOT NULL OR NEW.resolution_state != 'unresolved') THEN
                RAISE EXCEPTION 'local discussion has no protocol context' USING ERRCODE = '23514';
            END IF;
            IF NEW.topic_id IS NOT NULL AND NOT EXISTS
                (SELECT 1 FROM posts WHERE id=NEW.topic_id AND community_id=NEW.community_id AND parent_id IS NULL) THEN
                RAISE EXCEPTION 'discussion topic must belong to its community' USING ERRCODE = '23514';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER communities_identity BEFORE INSERT OR UPDATE ON communities
    FOR EACH ROW EXECUTE FUNCTION commune_identity_guard();
CREATE TRIGGER posts_identity BEFORE INSERT OR UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION commune_identity_guard();
CREATE TRIGGER contexts_identity BEFORE INSERT OR UPDATE ON discussion_contexts
    FOR EACH ROW EXECUTE FUNCTION commune_identity_guard();
