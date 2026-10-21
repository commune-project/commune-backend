-- Remember accepted reaction actions beyond their current active/undone state.
-- A replayed old Like must not become a new occurrence after an Undo.
CREATE TABLE applied_reaction_activities (
    activity_uri text PRIMARY KEY REFERENCES activities(uri)
);
