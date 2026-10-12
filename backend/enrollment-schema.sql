-- Additive, isolated internal-beta enrollment. Existing paid quotas are untouched.
CREATE TABLE IF NOT EXISTS remap_enrollment_limits (
  id integer PRIMARY KEY CHECK (id = 1),
  subject_limit integer NOT NULL DEFAULT 100,
  window_started timestamptz NOT NULL DEFAULT now(),
  window_used integer NOT NULL DEFAULT 0
);
INSERT INTO remap_enrollment_limits (id) VALUES (1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS remap_access_subjects (
  subject_hash text PRIMARY KEY CHECK (length(subject_hash) = 64),
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);
CREATE TABLE IF NOT EXISTS remap_access_tokens (
  token_hash text PRIMARY KEY CHECK (length(token_hash) = 64),
  subject_hash text NOT NULL REFERENCES remap_access_subjects(subject_hash),
  installation_hash text NOT NULL CHECK (length(installation_hash) = 64),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  UNIQUE(subject_hash, installation_hash)
);
CREATE OR REPLACE FUNCTION remap_enroll(subject text, installation text, token text, expiry timestamptz)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE quota integer; existing remap_access_tokens%ROWTYPE;
BEGIN
  -- Serialize enrollment decisions so concurrent requests cannot bypass either cap.
  SELECT subject_limit INTO quota FROM remap_enrollment_limits WHERE id = 1 FOR UPDATE;
  IF EXISTS(SELECT 1 FROM remap_access_subjects WHERE subject_hash = subject AND revoked_at IS NOT NULL) THEN
    RETURN 'revoked';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM remap_access_subjects WHERE subject_hash = subject) THEN
    IF (SELECT count(*) FROM remap_access_subjects) >= quota THEN RETURN 'limited'; END IF;
    INSERT INTO remap_access_subjects(subject_hash) VALUES(subject);
  END IF;
  SELECT * INTO existing FROM remap_access_tokens WHERE subject_hash = subject AND installation_hash = installation;
  IF FOUND THEN
    IF existing.revoked_at IS NOT NULL THEN RETURN 'revoked'; END IF;
    UPDATE remap_access_tokens SET token_hash = token, expires_at = expiry
      WHERE subject_hash = subject AND installation_hash = installation;
  ELSE
    IF (SELECT count(*) FROM remap_access_tokens WHERE subject_hash = subject) >= 5 THEN RETURN 'limited'; END IF;
    INSERT INTO remap_access_tokens(token_hash,subject_hash,installation_hash,expires_at)
      VALUES(token,subject,installation,expiry);
  END IF;
  RETURN 'ok';
END $$;
