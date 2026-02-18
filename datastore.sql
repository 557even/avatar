-----------------------------------------------------------------
-- 0️⃣  Extensions
-----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;   -- provides the `vector` type

-----------------------------------------------------------------
-- 1️⃣  Identity & access
-----------------------------------------------------------------
CREATE TABLE users (
    user_id      BIGSERIAL PRIMARY KEY,
    username     TEXT      NOT NULL UNIQUE,
    email        CITEXT    NOT NULL UNIQUE,
    full_name    TEXT,
    password_hash TEXT      NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE roles (
    role_id   BIGSERIAL PRIMARY KEY,
    role_name user_role NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE user_roles (
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    role_id BIGINT NOT NULL REFERENCES roles(role_id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE api_keys (
    api_key_id BIGSERIAL PRIMARY KEY,
    user_id    BIGINT      NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    key_name   TEXT        NOT NULL,
    key_secret TEXT        NOT NULL,               -- stored encrypted
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at TIMESTAMPTZ
);

-----------------------------------------------------------------
-- 2️⃣  Sessions & conversational flow
-----------------------------------------------------------------
CREATE TABLE sessions (
    session_id    BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(user_id) ON DELETE SET NULL,
    started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at      TIMESTAMPTZ,
    metadata      JSONB DEFAULT '{}'::jsonb,
    CONSTRAINT chk_session_times CHECK (ended_at IS NULL OR ended_at > started_at)
);

CREATE TABLE messages (
    message_id    BIGSERIAL PRIMARY KEY,
    session_id    BIGINT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    role          message_role NOT NULL,
    content       TEXT,                         -- plain text or JSON for multimodal payloads
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata      JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE media (
    media_id      BIGSERIAL PRIMARY KEY,
    storage_uri   TEXT NOT NULL,                -- S3, GCS, local path, etc.
    media_type    media_type NOT NULL,
    mime_type     TEXT,
    size_bytes    BIGINT,
    checksum_sha256 TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata      JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE message_media (
    message_id BIGINT NOT NULL REFERENCES messages(message_id) ON DELETE CASCADE,
    media_id   BIGINT NOT NULL REFERENCES media(media_id)   ON DELETE CASCADE,
    PRIMARY KEY (message_id, media_id)
);

-----------------------------------------------------------------
-- 3️⃣  Raw content & chunking
-----------------------------------------------------------------
CREATE TABLE documents (
    document_id  BIGSERIAL PRIMARY KEY,
    title        TEXT NOT NULL,
    source_uri   TEXT,                     -- original location, e.g. a URL or internal file ID
    doc_type     TEXT,                     -- e.g. "research_paper", "faq", "policy"
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata     JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE chunks (
    chunk_id     BIGSERIAL PRIMARY KEY,
    document_id  BIGINT NOT NULL REFERENCES documents(document_id) ON DELETE CASCADE,
    chunk_index  INT NOT NULL,            -- order of chunk within the doc
    text         TEXT NOT NULL,
    token_count  INT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata     JSONB DEFAULT '{}'::jsonb,
    UNIQUE (document_id, chunk_index)
);

-----------------------------------------------------------------
-- 4️⃣  Vector‑store catalog
-----------------------------------------------------------------
CREATE TABLE vector_stores (
    store_id          BIGSERIAL PRIMARY KEY,
    store_name        TEXT NOT NULL UNIQUE,
    provider          TEXT NOT NULL,                 -- e.g. "pinecone", "milvus", "weaviate"
    endpoint_url      TEXT NOT NULL,
    api_key           TEXT NOT NULL,                 -- encrypted JSON, keep secret
    dimension         INT NOT NULL,                  -- dimensionality of vectors
    metric            TEXT NOT NULL DEFAULT 'cosine',
    purpose           TEXT NOT NULL,                 -- "context", "findings", "analysis", …
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata          JSONB DEFAULT '{}'::jsonb
);

-----------------------------------------------------------------
-- 5️⃣  Embeddings (metadata + optional local copy)
-----------------------------------------------------------------
CREATE TABLE embeddings (
    embedding_id    BIGSERIAL PRIMARY KEY,
    store_id       BIGINT NOT NULL REFERENCES vector_stores(store_id) ON DELETE CASCADE,
    entity_type    TEXT NOT NULL,                     -- e.g. 'chunk', 'analysis', 'finding', 'media'
    entity_id      BIGINT NOT NULL,                    -- FK to the concrete table (no formal DB‑FK for flexibility)
    external_id    TEXT NOT NULL,                     -- ID returned by the external vector DB
    vector         VECTOR(1536),                      -- optional local storage; dimension must match store.dimension
    metadata       JSONB DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (store_id, external_id)
);

-- Optional: index for fast similarity search (only needed if `vector` column is used)
CREATE INDEX embeddings_vec_idx
    ON embeddings USING ivfflat (vector vector_cosine_ops) WITH (lists = 100);

-----------------------------------------------------------------
-- 6️⃣  Retrieval logs (what vectors were looked‑up for a request)
-----------------------------------------------------------------
CREATE TABLE retrieval_logs (
    retrieval_id    BIGSERIAL PRIMARY KEY,
    request_id     BIGINT NOT NULL REFERENCES llm_requests(request_id) ON DELETE CASCADE,
    store_id        BIGINT NOT NULL REFERENCES vector_stores(store_id) ON DELETE RESTRICT,
    query_vector   VECTOR(1536) NOT NULL,
    top_k          INT NOT NULL,
    result_ids     JSONB NOT NULL,                     -- array of external_id strings
    distances      JSONB,                              -- parallel array of similarity scores
    status         retrieval_status NOT NULL DEFAULT 'completed',
    retrieved_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-----------------------------------------------------------------
-- 7️⃣  LLM catalog & run‑time logs
-----------------------------------------------------------------
CREATE TABLE llm_models (
    model_id        BIGSERIAL PRIMARY KEY,
    provider        TEXT NOT NULL,                     -- e.g. "openai", "anthropic"
    model_name      TEXT NOT NULL,
    model_version   TEXT NOT NULL,
    endpoint_url    TEXT NOT NULL,
    max_context_len INT NOT NULL,
    supported_modalities JSONB,                         -- e.g. ["text","image"]
    default_params  JSONB DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, model_name, model_version)
);

CREATE TABLE llm_requests (
    request_id      BIGSERIAL PRIMARY KEY,
    session_id      BIGINT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    user_id         BIGINT NOT NULL REFERENCES users(user_id) ON DELETE SET NULL,
    model_id        BIGINT NOT NULL REFERENCES llm_models(model_id) ON DELETE RESTRICT,
    prompt_text     TEXT,                               -- plain text prompt (could be NULL if prompt_id used)
    prompt_json     JSONB,                              -- richer multimodal prompt representation
    parameters      JSONB DEFAULT '{}'::jsonb,          -- temperature, top_p, max_new_tokens …
    token_estimate INT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE llm_responses (
    response_id    BIGSERIAL PRIMARY KEY,
    request_id     BIGINT NOT NULL REFERENCES llm_requests(request_id) ON DELETE CASCADE,
    role           message_role NOT NULL,               -- always `assistant` but kept for symmetry
    content        JSONB NOT NULL,                      -- could contain `text` and `media_refs`
    usage          JSONB NOT NULL,                      -- {"prompt_tokens":..., "completion_tokens":..., "total_tokens":...}
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-----------------------------------------------------------------
-- 8️⃣  Feedback & evaluation
-----------------------------------------------------------------
CREATE TABLE feedback (
    feedback_id    BIGSERIAL PRIMARY KEY,
    response_id    BIGINT NOT NULL REFERENCES llm_responses(response_id) ON DELETE CASCADE,
    rating         SMALLINT CHECK (rating BETWEEN 1 AND 5),
    comment        TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    metadata       JSONB DEFAULT '{}'::jsonb
);

-----------------------------------------------------------------
-- 9️⃣  Plugins / tool integration
-----------------------------------------------------------------
CREATE TABLE plugins (
    plugin_id      BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    version        TEXT NOT NULL,
    enabled        BOOLEAN NOT NULL DEFAULT true,
    config         JSONB DEFAULT '{}'::jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (name, version)
);

CREATE TABLE plugin_invocations (
    invocation_id BIGSERIAL PRIMARY KEY,
    session_id    BIGINT NOT NULL REFERENCES sessions(session_id) ON DELETE CASCADE,
    plugin_id    BIGINT NOT NULL REFERENCES plugins(plugin_id) ON DELETE RESTRICT,
    request      JSONB NOT NULL,
    response     JSONB,
    latency_ms   INT,
    invoked_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-----------------------------------------------------------------
-- 10️⃣  System‑wide key‑value settings
-----------------------------------------------------------------
CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-----------------------------------------------------------------
-- 11️⃣  Miscellaneous: indices for fast look‑ups
-----------------------------------------------------------------
-- Users: quick email / username search
CREATE UNIQUE INDEX uq_user_email ON users (email);
CREATE UNIQUE INDEX uq_user_username ON users (username);

-- Sessions: latest session per user
CREATE INDEX idx_sessions_user_started ON sessions (user_id, started_at DESC);

-- Messages: retrieval by session & order
CREATE INDEX idx_messages_session_created ON messages (session_id, created_at);

-- Chunks: full‑text search (optional, using pg_trgm)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_chunks_text_trgm ON chunks USING gin (text gin_trgm_ops);

-- Retrieval logs: anti‑spam lookup
CREATE INDEX idx_retrieval_logs_req ON retrieval_logs (request_id);

-- LLM requests: time‑series queries
CREATE INDEX idx_llm_requests_created ON llm_requests (created_at DESC);


-----------------------------------------------------------------
-- 0️⃣  Insert roles (once)
-----------------------------------------------------------------
INSERT INTO roles (role_name, description)
VALUES 
  ('admin',     'Full administrative rights'),
  ('operator',  'Can run sessions and invoke plugins'),
  ('researcher','Can view analytics and edit prompts'),
  ('viewer',    'Read‑only access')
ON CONFLICT DO NOTHING;

-----------------------------------------------------------------
-- 1️⃣  Create a user (admin)
-----------------------------------------------------------------
INSERT INTO users (username, email, full_name, password_hash)
VALUES (
  'rselvan',
  'rselvan@example.com',
  'Rajan Selvan',
  crypt('SuperSecret!2026', gen_salt('bf'))
)
RETURNING user_id;
-- → suppose the returned id is 101

-----------------------------------------------------------------
-- 2️⃣  Assign admin role
-----------------------------------------------------------------
INSERT INTO user_roles (user_id, role_id)
SELECT 101, role_id FROM roles WHERE role_name='admin';

-----------------------------------------------------------------
-- 3️⃣  Register a vector store for “context”
-----------------------------------------------------------------
INSERT INTO vector_stores
  (store_name, provider, endpoint_url, api_key, dimension, purpose, metadata)
VALUES
  ('ctx-pinecone', 'pinecone', 'https://example-pc.svc.us-east-1.pinecone.io',
   '{"key":"<encrypted>"}',
   1536,
   'context',
   '{"description":"high‑dimensional embeddings for user‑query context"}'
)
RETURNING store_id;
-- → store_id = 1

-----------------------------------------------------------------
-- 4️⃣  Add a raw document (e.g. a research brief)
-----------------------------------------------------------------
INSERT INTO documents (title, source_uri, doc_type, metadata)
VALUES 
  ('The Future of Multimodal LLMs',
   's3://my‑bucket/research/future-multimodal.pdf',
   'research_paper',
   '{"authors":["Doe, Jane","Smith, John"],"year":2025}')
RETURNING document_id;
-- → document_id = 42

-----------------------------------------------------------------
-- 5️⃣  Chunk the document (pretend we pre‑processed it)
-----------------------------------------------------------------
INSERT INTO chunks (document_id, chunk_index, text, token_count)
VALUES
  (42, 1, 'Multimodal language models combine text, vision, and audio …', 42),
  (42, 2, '… enabling agents to understand and generate across modalities.', 39)
RETURNING chunk_id;
-- → 101, 102

-----------------------------------------------------------------
-- 6️⃣  Upsert embeddings into the “context” store
-----------------------------------------------------------------
-- Assume we have already called Pinecone and received external IDs “vecA”, “vecB”
INSERT INTO embeddings
  (store_id, entity_type, entity_id, external_id, vector, metadata)
VALUES
  (1, 'chunk', 101, 'vecA', '[0.12,0.03,0.98, ...]','{"source":"pinecone"}'),
  (1, 'chunk', 102, 'vecB', '[0.07,0.44,0.55, ...]','{"source":"pinecone"}')
RETURNING embedding_id;
-- → 501, 502

-----------------------------------------------------------------
-- 7️⃣  Open a new session for the user
-----------------------------------------------------------------
INSERT INTO sessions (user_id, metadata)
VALUES (101, '{"device":"web","client_version":"2.3.1"}')
RETURNING session_id;
-- → session_id = 9001

-----------------------------------------------------------------
-- 8️⃣  User sends a message (query)
-----------------------------------------------------------------
INSERT INTO messages (session_id, role, content)
VALUES (9001, 'user', 'Explain how attention mechanisms work in multimodal LLMs.')
RETURNING message_id;
-- → msg_id = 30001

-----------------------------------------------------------------
-- 9️⃣  LLM request (uses model “gpt‑4‑vision”)
-----------------------------------------------------------------
-- first add the model (once)
INSERT INTO llm_models (provider, model_name, model_version, endpoint_url,
                         max_context_len, supported_modalities, default_params)
VALUES
  ('openai','gpt-4-vision','01','https://api.openai.com/v1/chat/completions',
   8192, '["text","image"]'::jsonb,
   '{"temperature":0.7,"max_new_tokens":512}'::jsonb)
ON CONFLICT DO NOTHING
RETURNING model_id;
-- → model_id = 77

-- now the request
INSERT INTO llm_requests
  (session_id, user_id, model_id, prompt_text, parameters, token_estimate)
VALUES
  (9001, 101, 77,
   'Explain how attention mechanisms work in multimodal LLMs.',
   '{"temperature":0.5,"top_p":0.95}'::jsonb,
   45)      -- rough estimate
RETURNING request_id;
-- → request_id = 4001

-----------------------------------------------------------------
-- 10️⃣  Retrieval log – we query the “context” store for relevant chunks
-----------------------------------------------------------------
INSERT INTO retrieval_logs
  (request_id, store_id, query_vector, top_k, result_ids, distances, status)
VALUES
  (4001, 1,
   '[0.41,0.02,0.11, ...]'::vector,   -- query embedding produced by the LLM front‑end
   5,
   '["vecA","vecB"]'::jsonb,
   '[0.02,0.07]'::jsonb,
   'completed')
RETURNING retrieval_id;
-- → retrieval_id = 8001

-----------------------------------------------------------------
-- 11️⃣  LLM response (assistant message with a link to a generated image)
-----------------------------------------------------------------
INSERT INTO llm_responses
  (request_id, role, content, usage)
VALUES
  (4001, 'assistant',
   '{"text":"Attention in multimodal LLMs works by …","media_refs":[{"type":"image","uri":"s3://tmp/attention-diagram.png"}]}',
   '{"prompt_tokens":45,"completion_tokens":112,"total_tokens":157}'::jsonb)
RETURNING response_id;
-- → response_id = 5001

-----------------------------------------------------------------
-- 12️⃣  Store the assistant message in the conversation history
-----------------------------------------------------------------
INSERT INTO messages (session_id, role, content, metadata)
VALUES
  (9001, 'assistant',
   'Attention in multimodal LLMs works by … (see attached diagram).',
   '{"media_refs":[5001]}'::jsonb);

-----------------------------------------------------------------
-- 13️⃣  Collect user feedback
-----------------------------------------------------------------
INSERT INTO feedback (response_id, rating, comment, metadata)
VALUES
  (5001, 4, 'Pretty good but could use more concrete math.', '{}');

