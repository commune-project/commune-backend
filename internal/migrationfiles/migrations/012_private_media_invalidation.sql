-- Invalidation changes disposable generations, never authoritative uploads.
CREATE FUNCTION commune_invalidate_private_media() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_TABLE_NAME = 'posts' THEN
        IF NEW.deleted_at IS NOT NULL THEN
            UPDATE media_private_cache SET state='deleting',lease_until=now(),error_state='invalidated'
            WHERE post_id=NEW.id;
        END IF;
    ELSIF TG_TABLE_NAME = 'communities' THEN
        IF NEW.read_policy <> 'members' OR NEW.federation_mode <> 'federated' THEN
            UPDATE media_private_cache SET state='deleting',lease_until=now(),error_state='invalidated'
            WHERE access_scope=NEW.id;
        END IF;
    ELSIF TG_TABLE_NAME = 'site_posts' THEN
        IF NEW.hidden_at IS NOT NULL THEN
            UPDATE media_private_cache SET state='deleting',lease_until=now(),error_state='invalidated'
            WHERE site_id=NEW.site_id AND post_id=NEW.post_id;
        END IF;
    ELSIF TG_TABLE_NAME = 'collection_memberships' THEN
        IF NEW.state IN ('removed','rejected') AND NEW.community_id IS NOT NULL THEN
            UPDATE media_private_cache SET state='deleting',lease_until=now(),error_state='invalidated'
            WHERE post_id=NEW.post_id AND access_scope=NEW.community_id;
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER invalidate_deleted_post_media AFTER UPDATE OF deleted_at ON posts
FOR EACH ROW EXECUTE FUNCTION commune_invalidate_private_media();
CREATE TRIGGER invalidate_reclassified_media AFTER UPDATE OF read_policy,federation_mode ON communities
FOR EACH ROW EXECUTE FUNCTION commune_invalidate_private_media();
CREATE TRIGGER invalidate_hidden_media AFTER UPDATE OF hidden_at ON site_posts
FOR EACH ROW EXECUTE FUNCTION commune_invalidate_private_media();
CREATE TRIGGER invalidate_removed_media AFTER INSERT OR UPDATE ON collection_memberships
FOR EACH ROW EXECUTE FUNCTION commune_invalidate_private_media();
