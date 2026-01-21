DROP FUNCTION IF EXISTS pg_catalog.ogai_embedding(text, text, integer) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8920;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_embedding(text, text, integer)
    RETURNS vector
    LANGUAGE internal
    NOT FENCED NOT SHIPPABLE
AS 'ogai_embedding';

COMMENT ON FUNCTION pg_catalog.ogai_embedding(text, text, integer) IS 'return the embedding of a text';

DROP FUNCTION IF EXISTS pg_catalog.ogai_generate(text, text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8921;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_generate(text, text)
    RETURNS text
    LANGUAGE internal
    NOT FENCED NOT SHIPPABLE
AS 'ogai_generate';

COMMENT ON FUNCTION pg_catalog.ogai_generate(text, text) IS 'return the answer of a query using LLM';

DROP FUNCTION IF EXISTS pg_catalog.ogai_rerank(text, text[], text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8922;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_rerank(
    query text,
    documents text[],
    model text
)
    RETURNS TABLE(origin_index integer, document text, rerank_score double precision)
    LANGUAGE internal
    NOT FENCED NOT SHIPPABLE
AS 'ogai_rerank';

COMMENT ON FUNCTION pg_catalog.ogai_rerank(text, text[], text) IS 'return the rerank results of documents for query';

DROP FUNCTION IF EXISTS pg_catalog.ogai_chunk(text, integer, integer) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8925;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_chunk(
    documents text,
    max_chunk_size integer,
    max_chunk_overlap integer
)
    RETURNS TABLE(chunk_id integer, chunk text)
    LANGUAGE internal
    NOT FENCED NOT SHIPPABLE
AS 'ogai_chunk';

COMMENT ON FUNCTION pg_catalog.ogai_chunk(text, integer, integer) IS 'return the chunks results of documents with overlap';

DROP FUNCTION IF EXISTS pg_catalog.load_onnx_model(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8926;
CREATE OR REPLACE FUNCTION pg_catalog.load_onnx_model(text)
    RETURNS boolean
    LANGUAGE internal
    STRICT NOT FENCED NOT SHIPPABLE
AS 'load_onnx_model';

COMMENT ON FUNCTION pg_catalog.load_onnx_model(text) IS 'load an ONNX model into cache by model_key';

DROP FUNCTION IF EXISTS pg_catalog.unload_onnx_model(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8927;
CREATE OR REPLACE FUNCTION pg_catalog.unload_onnx_model(text)
    RETURNS boolean
    LANGUAGE internal
    STRICT NOT FENCED NOT SHIPPABLE
AS 'unload_onnx_model';

COMMENT ON FUNCTION pg_catalog.unload_onnx_model(text) IS 'upload an ONNX model from cache by model_key';

CREATE SCHEMA IF NOT EXISTS ogai;
GRANT USAGE ON SCHEMA ogai TO PUBLIC;

DO $$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type WHERE typname = 'model_provider_type' AND typnamespace = (SELECT oid FROM pg_catalog.pg_namespace WHERE nspname = 'ogai')) THEN
    CREATE TYPE ogai.model_provider_type AS ENUM (
        'openai',
        'onnx',
        'ollama',
        'Qwen'
    );
    GRANT USAGE ON TYPE ogai.model_provider_type TO PUBLIC;
END IF;
END $$;

CREATE TABLE IF NOT EXISTS ogai.model_sources
(
    id BIGINT UNIQUE,
    model_key   TEXT NOT NULL,
    model_name  TEXT NOT NULL,
    model_provider ogai.model_provider_type NOT NULL,
    url         VARCHAR(2048) NOT NULL,
    description TEXT DEFAULT '',
    api_key     TEXT,
    owner_name  TEXT NOT NULL,
    UNIQUE (model_key, owner_name)
);

DO $$ BEGIN
IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'model_sources_model_key_idx') THEN
    CREATE INDEX model_sources_model_key_idx ON ogai.model_sources (model_key);
END IF;
IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_indexes WHERE indexname = 'model_sources_owner_name_idx') THEN
    CREATE INDEX model_sources_owner_name_idx ON ogai.model_sources (owner_name);
END IF;
END $$;

DROP FUNCTION IF EXISTS pg_catalog.ogai_notify() CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8928;
CREATE FUNCTION pg_catalog.ogai_notify()
RETURNS void
AS 'ogai_notify'
LANGUAGE INTERNAL
STRICT;

COMMENT ON FUNCTION pg_catalog.ogai_notify() IS 'notify ogai aysnc worker thread';