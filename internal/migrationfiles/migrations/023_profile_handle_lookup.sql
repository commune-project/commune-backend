CREATE INDEX actors_acct_person_lower
    ON actors (lower(acct))
    WHERE acct <> '' AND kind = 'Person' AND local_site_id IS NULL;

CREATE TABLE profile_resolve_limits (
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    window_start timestamptz NOT NULL,
    attempts integer NOT NULL,
    PRIMARY KEY (site_id, account_id),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
