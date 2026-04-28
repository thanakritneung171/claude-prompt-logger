-- Claude Prompt Logger tables
-- Run once: npm run db:apply  (remote) or npm run db:apply:local (local dev)
-- These tables are additive — existing form-system-db tables are not affected.

CREATE TABLE IF NOT EXISTS prompt_logs (
  id            TEXT    PRIMARY KEY,
  session_id    TEXT    NOT NULL,
  cwd           TEXT    NOT NULL DEFAULT '',
  char_count    INTEGER NOT NULL DEFAULT 0,
  approx_tokens INTEGER NOT NULL DEFAULT 0,
  prompt        TEXT    NOT NULL DEFAULT '',
  logged_at     INTEGER NOT NULL   -- Unix ms (Date.now())
);

CREATE TABLE IF NOT EXISTS usage_logs (
  id                          TEXT    PRIMARY KEY,
  session_id                  TEXT    NOT NULL,
  model                       TEXT    NOT NULL DEFAULT '',
  input_tokens                INTEGER NOT NULL DEFAULT 0,
  output_tokens               INTEGER NOT NULL DEFAULT 0,
  cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
  cache_read_input_tokens     INTEGER NOT NULL DEFAULT 0,
  total_tokens                INTEGER NOT NULL DEFAULT 0,
  logged_at                   INTEGER NOT NULL   -- Unix ms
);

CREATE INDEX IF NOT EXISTS idx_prompt_logs_session    ON prompt_logs(session_id);
CREATE INDEX IF NOT EXISTS idx_prompt_logs_logged_at  ON prompt_logs(logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_session     ON usage_logs(session_id);
CREATE INDEX IF NOT EXISTS idx_usage_logs_logged_at   ON usage_logs(logged_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_logs_model       ON usage_logs(model);
