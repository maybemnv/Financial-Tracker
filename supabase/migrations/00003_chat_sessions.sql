-- ============================================================================
-- Chat session persistence for the Claude agent.
--
-- Matches the app's locked architecture: single anon key, NO auth
-- (see ARCHITECTURE.md). Like every other table in 00001_init.sql this table is
-- global — there is no user_id / auth.users FK to satisfy, because the app never
-- establishes an authenticated user. The agent keeps one rolling session: the
-- client loads the most recently updated row on launch and rewrites it after
-- each completed turn. RLS matches the 00001 pattern exactly.
-- ============================================================================

CREATE TABLE chat_sessions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  messages   JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE chat_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_all" ON chat_sessions FOR ALL USING (true);

CREATE INDEX idx_chat_sessions_updated ON chat_sessions(updated_at DESC);

CREATE TRIGGER set_chat_sessions_updated_at
  BEFORE UPDATE ON chat_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
