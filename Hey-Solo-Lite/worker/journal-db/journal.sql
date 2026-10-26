-- For the SEPARATE journal database (heysolo-journal).
-- Optional: the worker creates these tables by itself on first use.
-- Run this ONLY on the main journal database (heysolo-journal). The extra databases (JOURNAL_DB2..9) need nothing: the worker prepares them itself.
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
CREATE TABLE IF NOT EXISTS journal_shots (
  login TEXT NOT NULL,
  name TEXT NOT NULL,
  idx INTEGER NOT NULL,
  data TEXT NOT NULL,
  size INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(login, name, idx)
);
CREATE TABLE IF NOT EXISTS shot_index (
  login TEXT NOT NULL,
  name TEXT NOT NULL,
  shard INTEGER NOT NULL,
  size INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(login, name)
);
CREATE INDEX IF NOT EXISTS idx_shot_shard ON shot_index(shard, created_at);
CREATE INDEX IF NOT EXISTS idx_shot_time ON shot_index(created_at);
