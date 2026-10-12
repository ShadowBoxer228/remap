import { Hono } from 'hono';
import { bodyLimit } from 'hono/body-limit';
import { timingSafeEqual } from 'node:crypto';
import { neon } from '@neondatabase/serverless';
import { infer, prepare, issueVoiceToken } from './coach.mjs';
import { coverRoutes, coverDatabase } from './covers.mjs';
import { installationAccess, enrollmentDatabase, appleInstallationVerifier } from './enrollment.mjs';

function logFailure(route, error) {
  // Operational codes only: never log input, credentials, raw upstream messages or audio.
  const code = typeof error?.code === 'string' && /^[a-z0-9_]{1,80}$/i.test(error.code) ? error.code : 'unavailable';
  console.warn(JSON.stringify({ event: 'coach_failure', route, code }));
}

export function databaseReserve(url) {
  return async kind => {
    const sql = neon(url, { fetchOptions: { signal: AbortSignal.timeout(8000) } });
    // One atomic row update: concurrent instances cannot overrun the shared cap.
    const rows = await sql`UPDATE coach_quota SET used = used + 1,
      window_used = CASE WHEN window_started <= now() - interval '1 minute' THEN 1 ELSE window_used + 1 END,
      window_started = CASE WHEN window_started <= now() - interval '1 minute' THEN now() ELSE window_started END
      WHERE kind = ${kind} AND (request_limit IS NULL OR used < request_limit)
        AND (window_started <= now() - interval '1 minute' OR window_used < 12)
      RETURNING used`;
    return rows.length === 1;
  };
}

export function gateway({ key, token, reserve, inferFn = infer, tokenFn = issueVoiceToken, coverKey, coverRepository, access }) {
  const app = new Hono();
  app.use('*', async (c, next) => { c.header('Cache-Control', 'no-store'); await next(); });
  app.get('/health', c => c.json({ status: 'ok', provider: 'openai-realtime', configured: Boolean(key && token && reserve) }));
  app.post('/access/enroll', bodyLimit({ maxSize: 32768, onError: c => c.json({ error: 'request_too_large' }, 413) }), async c => {
    if (!access?.configured) return c.json({ error: 'enrollment_unavailable' }, 503);
    let input;
    try { input = await c.req.json(); } catch { return c.json({ error: 'invalid_enrollment' }, 400); }
    try { const result = await access.enroll(input); return c.json(result.body, result.status); }
    catch { return c.json({ error: 'enrollment_unavailable' }, 503); }
  });
  app.use('*', async (c, next) => {
    const credential = c.req.header('X-ReMap-Token') ?? c.req.header('Authorization')?.replace(/^Bearer /, '') ?? '';
    if (credential.length > 256) return c.json({ error: 'unauthorized' }, 401);
    const actual = Buffer.from(credential);
    const expected = Buffer.from(token ?? '');
    const legacy = expected.length >= 32 && actual.length === expected.length && timingSafeEqual(actual, expected);
    if (!legacy && !await access?.authorize(credential)) return c.json({ error: 'unauthorized' }, 401);
    if (!key || !reserve) return c.json({ error: 'not_configured' }, 503);
    await next();
  });
  app.use('*', bodyLimit({ maxSize: 32768, onError: c => c.json({ error: 'request_too_large' }, 413) }));
  app.post('/coach', async c => {
    let input;
    try { input = await c.req.json(); prepare(input); }
    catch { return c.json({ error: 'invalid_request' }, 400); }
    try {
      if (!await reserve('text')) return c.json({ error: 'request_limit' }, 429);
      return c.json(await inferFn(input, key));
    } catch (error) { logFailure('coach', error); return c.json({ error: 'coach_unavailable' }, 503); }
  });
  app.post('/realtime/token', async c => {
    let profile;
    try { profile = (await c.req.json()).profile; }
    catch { return c.json({ error: 'invalid_request' }, 400); }
    if (profile !== undefined && profile !== 'conversation') return c.json({ error: 'invalid_request' }, 400);
    try {
      // No client-supplied session config or model is accepted here.
      if (!await reserve('voice')) return c.json({ error: 'request_limit' }, 429);
      return c.json(await tokenFn(key, fetch, profile === 'conversation'));
    } catch (error) { logFailure('voice', error); return c.json({ error: 'voice_unavailable' }, 503); }
  });
  app.route('/covers', coverRoutes({ key: coverKey, repository: coverRepository }));
  app.notFound(c => c.json({ error: 'not_found' }, 404));
  app.onError((_error, c) => c.json({ error: 'unavailable' }, 503));
  return app;
}

export default gateway({ key: process.env.OPENAI_API_KEY, token: process.env.REMAP_ACCESS_TOKEN,
  reserve: process.env.DATABASE_URL ? databaseReserve(process.env.DATABASE_URL) : undefined,
  coverKey: process.env.FAL_KEY,
  coverRepository: process.env.DATABASE_URL ? coverDatabase(process.env.DATABASE_URL) : undefined,
  access: installationAccess({ secret: process.env.REMAP_ENROLLMENT_SECRET,
    repository: process.env.DATABASE_URL ? enrollmentDatabase(process.env.DATABASE_URL) : undefined,
    verify: appleInstallationVerifier(process.env.REMAP_APP_APPLE_ID) }) });
