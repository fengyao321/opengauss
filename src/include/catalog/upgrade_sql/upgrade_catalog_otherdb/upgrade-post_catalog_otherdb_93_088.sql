DROP FUNCTION IF EXISTS pg_catalog.ogai_embedding(text, text, integer) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8920;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_embedding(text, text, integer)
    RETURNS vector
    LANGUAGE internal
    STABLE NOT FENCED
AS 'ogai_embedding';

COMMENT ON FUNCTION pg_catalog.ogai_embedding(text, text, integer) IS 'return the embedding of a text';

DROP FUNCTION IF EXISTS pg_catalog.ogai_generate(text, text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8921;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_generate(text, text)
    RETURNS text
    LANGUAGE internal
    STABLE NOT FENCED
AS 'ogai_generate';

COMMENT ON FUNCTION pg_catalog.ogai_generate(text, text) IS 'return the answer of a query using LLM';

DROP FUNCTION IF EXISTS pg_catalog.ogai_rerank(text, text[], text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8922;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_rerank(
    query text,
    documents text[],
    model text,
    OUT origin_index integer,
    OUT document text,
    OUT rerank_score double precision
)
    RETURNS SETOF record
    LANGUAGE internal
    STABLE NOT FENCED ROWS 5
AS 'ogai_rerank';

COMMENT ON FUNCTION pg_catalog.ogai_rerank(text, text[], text) IS 'return the rerank results of documents for query';

DROP FUNCTION IF EXISTS pg_catalog.ogai_chunk(text, integer, integer) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8925;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_chunk(
    documents text,
    max_chunk_size integer,
    max_chunk_overlap integer,
    OUT chunk_id integer,
    OUT chunk text
)
    RETURNS SETOF record
    LANGUAGE internal
    STABLE NOT FENCED ROWS 5
AS 'ogai_chunk';

COMMENT ON FUNCTION pg_catalog.ogai_chunk(text, integer, integer) IS 'return the chunks results of documents with overlap';

DROP FUNCTION IF EXISTS pg_catalog.load_onnx_model(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8926;
CREATE OR REPLACE FUNCTION pg_catalog.load_onnx_model(text)
    RETURNS boolean
    LANGUAGE internal
    STABLE NOT FENCED
AS 'load_onnx_model';

COMMENT ON FUNCTION pg_catalog.load_onnx_model(text) IS 'load an ONNX model into cache by model_key';

DROP FUNCTION IF EXISTS pg_catalog.unload_onnx_model(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8927;
CREATE OR REPLACE FUNCTION pg_catalog.unload_onnx_model(text)
    RETURNS boolean
    LANGUAGE internal
    STABLE NOT FENCED
AS 'unload_onnx_model';

COMMENT ON FUNCTION pg_catalog.unload_onnx_model(text) IS 'unload an ONNX model from cache by model_key';

-- NOTE: ogai schema, tables, types, RLS policies are now created dynamically
-- by LoadOgai() in postgres.cpp on first database connection.

DROP FUNCTION IF EXISTS pg_catalog.ogai_notify() CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8928;
CREATE FUNCTION pg_catalog.ogai_notify()
    RETURNS void
AS 'ogai_notify'
LANGUAGE INTERNAL
NOT FENCED;

COMMENT ON FUNCTION pg_catalog.ogai_notify() IS 'notify ogai async worker thread';

DROP FUNCTION IF EXISTS pg_catalog.ogai_encrypt_api_key(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8929;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_encrypt_api_key(text)
    RETURNS text
    LANGUAGE internal
    STABLE NOT FENCED
AS 'ogai_encrypt_api_key';

COMMENT ON FUNCTION pg_catalog.ogai_encrypt_api_key(text) IS 'encrypt api_key for secure storage in ogai.model_sources';

DROP FUNCTION IF EXISTS pg_catalog.ogai_decrypt_api_key(text) CASCADE;
SET LOCAL inplace_upgrade_next_system_object_oids=IUO_PROC, 8931;
CREATE OR REPLACE FUNCTION pg_catalog.ogai_decrypt_api_key(text)
    RETURNS text
    LANGUAGE internal
    STABLE NOT FENCED
AS 'ogai_decrypt_api_key';

COMMENT ON FUNCTION pg_catalog.ogai_decrypt_api_key(text) IS 'decrypt api_key from ogai.model_sources for viewing';
