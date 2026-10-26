CREATE TABLE IF NOT EXISTS journal_data (
  login TEXT PRIMARY KEY,
  journal_json TEXT NOT NULL DEFAULT '{}',
  oldest_trade_at INTEGER NOT NULL DEFAULT 0,
  prune_before_ts INTEGER NOT NULL DEFAULT 0,
  notes_json TEXT NOT NULL DEFAULT '{}',
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_journal_budget ON journal_data(oldest_trade_at, login);
CREATE TABLE IF NOT EXISTS journal_access (
  login TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
