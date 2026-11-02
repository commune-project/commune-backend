ALTER TABLE communities ADD COLUMN follow_policy text NOT NULL DEFAULT 'open'
    CHECK (follow_policy IN ('open','members','approval','disabled'));
UPDATE communities SET follow_policy='members' WHERE read_policy='members';

CREATE INDEX follows_accepted ON follows(community_id) WHERE state='accepted';
CREATE INDEX follows_pending ON follows(community_id, updated_at) WHERE state='pending';
