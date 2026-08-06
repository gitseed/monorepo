-- Phase 2 schema: one row per memory.
-- id is BIGINT (postgres has no unsigned 64-bit type).
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS memories (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id  UUID        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- heard = something the user said, said = something the agent said,
    -- thought = agent thinking block, remembered = explicitly saved
    -- via the remember tool.
    kind        TEXT        NOT NULL CHECK (kind IN ('heard', 'said', 'thought', 'remembered')),
    summary     TEXT,
    content     TEXT        NOT NULL,
    content_len INTEGER     GENERATED ALWAYS AS (length(content)) STORED,
    -- Cosine-searchable embedding of content (openai/text-embedding-3-small);
    -- filled in asynchronously after insert, NULL until then.
    embedding   vector(1536),
    suppressed  BOOLEAN     NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS memories_session_idx ON memories (session_id, id);
CREATE INDEX IF NOT EXISTS memories_embedding_idx ON memories
    USING hnsw (embedding vector_cosine_ops);
