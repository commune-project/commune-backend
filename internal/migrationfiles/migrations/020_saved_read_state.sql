CREATE TABLE saved_posts (
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    post_id text NOT NULL REFERENCES posts(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, account_id, post_id),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX saved_posts_page ON saved_posts(site_id, account_id, created_at DESC, post_id);

CREATE TABLE post_reads (
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    post_id text NOT NULL REFERENCES posts(id),
    read_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, account_id, post_id),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX post_reads_page ON post_reads(site_id, account_id, read_at DESC, post_id);

CREATE TABLE post_hidden (
    site_id text NOT NULL REFERENCES sites(id),
    account_id bigint NOT NULL,
    post_id text NOT NULL REFERENCES posts(id),
    hidden_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (site_id, account_id, post_id),
    FOREIGN KEY (site_id, account_id) REFERENCES accounts(site_id, id)
);
CREATE INDEX post_hidden_page ON post_hidden(site_id, account_id, hidden_at DESC, post_id);
