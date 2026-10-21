-- Optional source/attachment/tag metadata is author data, never display HTML.
-- Keep an empty default for existing and legacy objects, matching PostRecord's
-- zero value and the explicit SQL used by federation reception.
ALTER TABLE posts ADD COLUMN rich_metadata text NOT NULL DEFAULT '';
