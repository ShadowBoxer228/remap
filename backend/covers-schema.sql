-- Independent of coach quotas. Reapplying this migration never resets usage.
CREATE TABLE IF NOT EXISTS remap_cover_quota (
  name text PRIMARY KEY CHECK (name = 'covers'),
  used integer NOT NULL DEFAULT 0 CHECK (used >= 0),
  request_limit integer DEFAULT 100 CHECK (request_limit > 0)
);
-- NULL supports explicitly enabled unlimited usage; existing counters/caps are preserved.
ALTER TABLE remap_cover_quota ALTER COLUMN request_limit DROP NOT NULL;
INSERT INTO remap_cover_quota(name) VALUES ('covers') ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS remap_cover_jobs (
  id uuid PRIMARY KEY,
  session_id uuid NOT NULL,
  request_hash text NOT NULL,
  status text NOT NULL CHECK (status IN ('submitting','pending','ready','failed','uncertain','limited')),
  provider_id text,
  status_url text,
  response_url text,
  image_url text,
  error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
