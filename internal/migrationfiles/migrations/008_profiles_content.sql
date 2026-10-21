CREATE TABLE profiles (
    actor_uri text PRIMARY KEY,
    actor_kind text NOT NULL DEFAULT 'Person' CHECK (actor_kind = 'Person'),
    display_name text NOT NULL DEFAULT '',
    biography text NOT NULL DEFAULT '',
    biography_html text NOT NULL DEFAULT '',
    avatar_url text NOT NULL DEFAULT '',
    avatar_binding_id text NOT NULL DEFAULT '',
    updated_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (actor_uri, actor_kind) REFERENCES actors(uri, kind)
);

ALTER TABLE posts ADD COLUMN content_format text NOT NULL DEFAULT 'legacy'
    CHECK (content_format IN ('legacy','markdown','html'));
ALTER TABLE posts ADD COLUMN search_text text NOT NULL DEFAULT '';
UPDATE posts SET search_text = trim(regexp_replace(
    regexp_replace(coalesce(title,'') || ' ' || body,
        '<(script|style)[^>]*>.*?</\1\s*>', ' ', 'gis'),
    '<[^>]*>', ' ', 'g'));
