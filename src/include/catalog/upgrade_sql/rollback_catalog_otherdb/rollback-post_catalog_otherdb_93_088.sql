DROP FUNCTION IF EXISTS pg_catalog.unload_onnx_model(text);
DROP FUNCTION IF EXISTS pg_catalog.load_onnx_model(text);
DROP FUNCTION IF EXISTS pg_catalog.ogai_chunk(text, integer, integer);
DROP FUNCTION IF EXISTS pg_catalog.ogai_rerank(text, text[], text);
DROP FUNCTION IF EXISTS pg_catalog.ogai_generate(text, text);
DROP FUNCTION IF EXISTS pg_catalog.ogai_embedding(text, text, integer);
DROP FUNCTION IF EXISTS pg_catalog.ogai_notify();
DROP FUNCTION IF EXISTS pg_catalog.ogai_decrypt_api_key(text);
DROP FUNCTION IF EXISTS pg_catalog.ogai_encrypt_api_key(text);