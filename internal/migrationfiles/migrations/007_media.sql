-- Authoritative sources and disposable private cache bytes have separate tables.
CREATE TABLE media_uploads (
    id text PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    owner_account_id bigint NOT NULL REFERENCES accounts(id),
    purpose text NOT NULL CHECK (purpose IN ('post','avatar')),
    state text NOT NULL CHECK (state IN ('uploading','ready','deleting')),
    reserved_bytes bigint NOT NULL CHECK (reserved_bytes > 0),
    size_bytes bigint NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
    preview_bytes bigint NOT NULL DEFAULT 0 CHECK (preview_bytes >= 0),
    media_type text NOT NULL DEFAULT '',
    original_name text NOT NULL DEFAULT '',
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    lease_token text NOT NULL,
    lease_until timestamptz NOT NULL,
    UNIQUE (id,site_id,owner_account_id),
    CHECK (size_bytes + preview_bytes <= reserved_bytes)
);
CREATE INDEX media_upload_quota ON media_uploads(site_id,owner_account_id);
CREATE INDEX media_upload_cleanup ON media_uploads(state,expires_at,lease_until);
CREATE TABLE media_bindings (
    id text PRIMARY KEY,
    upload_id text NOT NULL UNIQUE,
    site_id text NOT NULL,
    owner_account_id bigint NOT NULL,
    purpose text NOT NULL CHECK (purpose IN ('post','avatar')),
    post_id text REFERENCES posts(id),
    active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (upload_id,site_id,owner_account_id)
        REFERENCES media_uploads(id,site_id,owner_account_id),
    CHECK ((purpose='post') = (post_id IS NOT NULL))
);
CREATE UNIQUE INDEX media_current_avatar ON media_bindings(site_id,owner_account_id)
    WHERE active AND purpose='avatar';
CREATE INDEX media_post_bindings ON media_bindings(post_id) WHERE active;
CREATE TABLE media_private_cache (
    id text PRIMARY KEY,
    site_id text NOT NULL REFERENCES sites(id),
    post_id text NOT NULL REFERENCES posts(id),
    origin_uri text NOT NULL,
    origin_version text NOT NULL,
    access_scope text NOT NULL,
    generation text NOT NULL,
    state text NOT NULL CHECK (state IN ('missing','fetching','ready','deleting')),
    fetched_at timestamptz,
    expires_at timestamptz,
    size_bytes bigint NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
    lease_token text NOT NULL DEFAULT '',
    lease_until timestamptz NOT NULL DEFAULT now(),
    error_state text NOT NULL DEFAULT '',
    UNIQUE (site_id,post_id,origin_uri,origin_version,access_scope)
);
CREATE INDEX media_cache_cleanup ON media_private_cache(state,expires_at,lease_until);
-- Cross-site ownership is enforced even when integration callers supply bad IDs.
CREATE FUNCTION commune_media_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM accounts WHERE id=NEW.owner_account_id AND site_id=NEW.site_id) THEN
        RAISE EXCEPTION 'media owner must belong to site' USING ERRCODE='23514';
    END IF;
    IF TG_TABLE_NAME='media_bindings' THEN
        IF NOT EXISTS (SELECT 1 FROM media_uploads WHERE id=NEW.upload_id AND purpose=NEW.purpose AND state='ready') THEN
            RAISE EXCEPTION 'binding requires ready upload of intended purpose' USING ERRCODE='23514';
        END IF;
        IF NEW.purpose='avatar' AND NOT EXISTS (SELECT 1 FROM media_uploads WHERE id=NEW.upload_id AND media_type IN ('image/png','image/jpeg','image/gif')) THEN
            RAISE EXCEPTION 'avatar requires validated raster image' USING ERRCODE='23514';
        END IF;
        IF NEW.active AND NEW.post_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM posts p JOIN accounts a ON a.actor_uri=p.author_actor_uri
            JOIN site_posts sp ON sp.post_id=p.id AND sp.site_id=NEW.site_id
            WHERE p.id=NEW.post_id AND a.id=NEW.owner_account_id AND a.site_id=NEW.site_id
                AND p.deleted_at IS NULL AND sp.hidden_at IS NULL
        ) THEN
            RAISE EXCEPTION 'post binding requires current site author reception' USING ERRCODE='23514';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER media_upload_owner BEFORE INSERT OR UPDATE ON media_uploads
    FOR EACH ROW EXECUTE FUNCTION commune_media_guard();
CREATE TRIGGER media_binding_owner BEFORE INSERT OR UPDATE ON media_bindings
    FOR EACH ROW EXECUTE FUNCTION commune_media_guard();
