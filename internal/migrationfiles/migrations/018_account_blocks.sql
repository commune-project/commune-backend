CREATE TABLE account_blocks (
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    kind text NOT NULL CHECK (kind IN ('person','community','instance')),
    target text NOT NULL CHECK (length(target) > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, account_id, kind, target),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX account_blocks_target ON account_blocks(site_id, kind, target);
