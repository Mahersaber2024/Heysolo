CREATE TABLE IF NOT EXISTS telegram_users (
  telegram_id TEXT PRIMARY KEY,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
  login          TEXT PRIMARY KEY,
  symbol         TEXT,
  broker         TEXT,
  currency       TEXT,
  server         TEXT,
  ea             TEXT,
  updated_at     INTEGER NOT NULL,
  card_json      TEXT,
  prop_json      TEXT,
  running_json   TEXT,
  dashboard_json TEXT,
  settings_json  TEXT
);

CREATE TABLE IF NOT EXISTS user_accounts (
  telegram_id TEXT NOT NULL,
  login       TEXT NOT NULL,
  PRIMARY KEY (telegram_id, login)
);
CREATE INDEX IF NOT EXISTS idx_user_accounts_login ON user_accounts(login);

CREATE TABLE IF NOT EXISTS ea_states (
  chart_key  TEXT PRIMARY KEY,
  login      TEXT NOT NULL,
  symbol     TEXT,
  state_json TEXT NOT NULL DEFAULT '{}',
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_ea_states_login ON ea_states(login, updated_at);

CREATE TABLE IF NOT EXISTS ea_commands (
  id           TEXT PRIMARY KEY,
  login        TEXT NOT NULL,
  symbol       TEXT,
  body         TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending',
  created_at   INTEGER NOT NULL,
  delivered_at INTEGER,
  ack_raw      TEXT
);
CREATE INDEX IF NOT EXISTS idx_ea_commands_queue ON ea_commands(login, symbol, status, created_at);

CREATE TABLE IF NOT EXISTS user_input_sessions (
  telegram_id TEXT PRIMARY KEY,
  chat_id     TEXT,
  chart_key   TEXT,
  field_index INTEGER,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS prop_alert_prefs (
  telegram_id TEXT NOT NULL,
  login       TEXT NOT NULL,
  enabled     INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (telegram_id, login)
);

CREATE TABLE IF NOT EXISTS prop_alert_state (
  login        TEXT PRIMARY KEY,
  failed       INTEGER NOT NULL DEFAULT 0,
  passed       INTEGER NOT NULL DEFAULT 0,
  daily_warned INTEGER NOT NULL DEFAULT 0,
  total_warned INTEGER NOT NULL DEFAULT 0,
  day_key      TEXT,
  updated_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS copier_channels (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  tx_hash    TEXT NOT NULL,
  rx_hash    TEXT NOT NULL,
  had_signal INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_copier_channels_tx ON copier_channels(tx_hash);
CREATE INDEX IF NOT EXISTS idx_copier_channels_rx ON copier_channels(rx_hash);

CREATE TABLE IF NOT EXISTS copier_signals (
  channel_id  TEXT NOT NULL,
  unique_id   TEXT NOT NULL,
  signal_json TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,
  closed_at   INTEGER,
  PRIMARY KEY (channel_id, unique_id)
);
