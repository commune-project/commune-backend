CREATE TABLE person_follows (
    local_actor_uri text NOT NULL REFERENCES actors(uri),
    follower_actor_uri text NOT NULL REFERENCES actors(uri),
    follow_uri text NOT NULL UNIQUE,
    state text NOT NULL CHECK (state IN ('pending','accepted','rejected','undone')),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (local_actor_uri, follower_actor_uri),
    CHECK (local_actor_uri != follower_actor_uri)
);
CREATE INDEX person_follows_local ON person_follows(local_actor_uri, state);

-- A Person follow targets a local site-owned Person and is issued by a Person.
CREATE FUNCTION commune_person_follow_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM actors WHERE uri=NEW.local_actor_uri AND kind='Person' AND local_site_id IS NOT NULL) THEN
        RAISE EXCEPTION 'person follow target must be a local Person' USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM actors WHERE uri=NEW.follower_actor_uri AND kind='Person') THEN
        RAISE EXCEPTION 'person follower must be a Person' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER person_follows_guard BEFORE INSERT OR UPDATE ON person_follows
    FOR EACH ROW EXECUTE FUNCTION commune_person_follow_guard();
