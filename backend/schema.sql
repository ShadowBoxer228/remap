CREATE TABLE IF NOT EXISTS coach_quota (
  kind text PRIMARY KEY CHECK (kind IN ('text', 'voice')),
  used integer NOT NULL DEFAULT 0 CHECK (used >= 0),
  request_limit integer CHECK (request_limit > 0),
  window_started timestamptz NOT NULL DEFAULT now(),
  window_used integer NOT NULL DEFAULT 0 CHECK (window_used >= 0)
);
INSERT INTO coach_quota (kind, request_limit) VALUES ('text', 200), ('voice', 10)
ON CONFLICT (kind) DO NOTHING;
