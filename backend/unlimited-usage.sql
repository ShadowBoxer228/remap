-- Explicitly requested by the owner on 2026-10-12. Retains all usage counters.
-- NULL means no lifetime count cap; it is not a provider spending/balance limit.
ALTER TABLE coach_quota ALTER COLUMN request_limit DROP NOT NULL;
ALTER TABLE remap_cover_quota ALTER COLUMN request_limit DROP NOT NULL;
UPDATE coach_quota SET request_limit = NULL WHERE kind IN ('text', 'voice');
UPDATE remap_cover_quota SET request_limit = NULL WHERE name = 'covers';
