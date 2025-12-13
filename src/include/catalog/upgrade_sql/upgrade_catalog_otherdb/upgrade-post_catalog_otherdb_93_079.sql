DROP FUNCTION IF EXISTS pg_catalog.ogai_notify() CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8928;
CREATE FUNCTION pg_catalog.ogai_notify()
RETURNS void
AS 'ogai_notify'
LANGUAGE INTERNAL
STRICT;

COMMENT ON FUNCTION pg_catalog.ogai_notify() IS 'notify ogai aysnc worker thread';