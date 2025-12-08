/*
 * Copyright (c) 2025 Huawei Technologies Co.,Ltd.
 *
 * openGauss is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 * ---------------------------------------------------------------------------------------
 *
 * ogai_tables.sql
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai_sql/ogai_tables.sql
 *
 * ---------------------------------------------------------------------------------------
 */

-- Create ogai schema
CREATE SCHEMA IF NOT EXISTS ogai;
GRANT USAGE ON SCHEMA ogai TO PUBLIC;

CREATE TYPE ogai.model_provider_type AS ENUM (
    'openai',
    'onnx',
    'ollama',
    'Qwen'
);
GRANT USAGE ON TYPE ogai.model_provider_type TO PUBLIC;

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
CREATE INDEX IF NOT EXISTS model_sources_model_key_idx ON ogai.model_sources (model_key);
CREATE INDEX IF NOT EXISTS model_sources_owner_name_idx ON ogai.model_sources (owner_name);
