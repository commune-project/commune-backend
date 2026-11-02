ALTER TABLE reactions ADD COLUMN score smallint NOT NULL DEFAULT 1 CHECK (score IN (-1,1));
CREATE INDEX reactions_active_post ON reactions(post_id, score) WHERE undone_at IS NULL;

ALTER TABLE activities DROP CONSTRAINT activities_kind_check;
ALTER TABLE activities ADD CONSTRAINT activities_kind_check
    CHECK (kind IN ('Create','Update','Delete','Like','Dislike','Undo','Follow','Accept','Reject','Announce','Add','Remove'));
