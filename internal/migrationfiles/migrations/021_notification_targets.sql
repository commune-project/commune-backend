ALTER TABLE notification_events ALTER COLUMN post_id DROP NOT NULL;
ALTER TABLE notification_events ADD COLUMN target_kind text NOT NULL DEFAULT 'post'
    CHECK (target_kind IN ('post','report','community','person','moderation'));
ALTER TABLE notification_events ADD COLUMN target_id text NOT NULL DEFAULT '';
UPDATE notification_events SET target_id=post_id WHERE post_id IS NOT NULL AND target_id='';

ALTER TABLE notification_events DROP CONSTRAINT notification_events_kind_check;
ALTER TABLE notification_events ADD CONSTRAINT notification_events_kind_check
    CHECK (kind IN ('reply','like','mention','report','moderation'));

CREATE FUNCTION commune_notification_target_default() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.target_kind='post' AND NEW.target_id='' AND NEW.post_id IS NOT NULL THEN
        NEW.target_id := NEW.post_id;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER notification_target_default BEFORE INSERT OR UPDATE ON notification_events
    FOR EACH ROW EXECUTE FUNCTION commune_notification_target_default();
