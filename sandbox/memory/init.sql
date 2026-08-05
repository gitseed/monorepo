-- Phase 1 schema: one row per conversational turn.
-- id is BIGINT (postgres has no unsigned 64-bit type).
CREATE TABLE IF NOT EXISTS turns (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id UUID        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- say = user prompt, steer = mid-run user injection,
    -- think = model thinking block, reply = model text.
    kind       TEXT        NOT NULL CHECK (kind IN ('say', 'steer', 'think', 'reply')),
    summary    TEXT,
    content    TEXT        NOT NULL
);

CREATE INDEX IF NOT EXISTS turns_session_idx ON turns (session_id, id);
