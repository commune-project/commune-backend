CREATE TABLE site_vote_settings (
    site_id text PRIMARY KEY REFERENCES sites(id),
    upvotes_enabled boolean NOT NULL DEFAULT true,
    downvotes_enabled boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by_actor_uri text REFERENCES actors(uri)
);
