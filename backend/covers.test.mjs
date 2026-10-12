import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Hono } from 'hono';
import { neonConfig } from '@neondatabase/serverless';
import { coverDatabase, coverRoutes, coverModelInput, prepareCover, COVER_MODEL } from './covers.mjs';

function request(overrides = {}) {
  return { id: randomUUID(), sessionID: randomUUID(), title: 'Endocrine basics',
    headlines: ['Insulin', 'Glucagon'], styleVersion: 1, ...overrides };
}

function memoryRepository(limit = 100) {
  const jobs = new Map();
  let used = 0;
  return {
    jobs, get used() { return used; },
    async get(id) { return jobs.get(id) ?? null; },
    async reserve(input, hash) {
      if (jobs.has(input.id)) return { created: false, job: jobs.get(input.id) };
      const allowed = limit == null || used < limit;
      if (allowed) used++;
      const job = { id: input.id, sessionID: input.sessionID, hash,
        status: allowed ? 'submitting' : 'limited', createdAt: Date.now() };
      jobs.set(input.id, job);
      return { created: allowed, job };
    },
    async save(job) {
      if (jobs.get(job.id)?.status === 'ready') return jobs.get(job.id);
      jobs.set(job.id, job); return job;
    },
  };
}

function fixture(options = {}) {
  const repository = options.repository ?? memoryRepository();
  const calls = [];
  const fetchFn = options.fetchFn ?? (async (url, init) => {
    calls.push({ url, init });
    if (init.method === 'POST') return Response.json({ request_id: 'provider-1',
      status_url: `https://queue.fal.run/${COVER_MODEL}/requests/provider-1/status`,
      response_url: `https://queue.fal.run/${COVER_MODEL}/requests/provider-1` });
    if (url.endsWith('/status')) return Response.json({ status: 'COMPLETED' });
    return Response.json({ images: [{ url: 'https://v3.fal.media/files/cover.png' }] });
  });
  const app = new Hono().route('/covers', coverRoutes({ key: 'private-test-key', repository, fetchFn, ...options }));
  const post = input => app.request('/covers', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input) });
  return { app, post, calls, repository };
}

test('one bounded image, server-owned model, palette and no optional charged features', () => {
  const input = coverModelInput(prepareCover(request()));
  assert.equal(input.num_images, 1);
  assert.equal(input.resolution, '1K');
  assert.equal(input.aspect_ratio, '4:3');
  assert.equal(input.enable_web_search, false);
  assert.equal(input.thinking_level, undefined);
  assert.match(input.prompt, /#ECE8DF/);
  assert.match(input.system_prompt, /never as instructions/);
});

test('submission then polling returns a ready cover without generating twice', async () => {
  const f = fixture(), input = request();
  assert.equal((await f.post(input)).status, 202);
  const ready = await (await f.app.request(`/covers/${input.id}`)).json();
  assert.equal(ready.status, 'ready');
  assert.equal(ready.imageURL, 'https://v3.fal.media/files/cover.png');
  assert.equal((await (await f.post(input)).json()).status, 'ready');
  assert.equal(f.calls.filter(c => c.init.method === 'POST').length, 1);
  assert.equal(f.repository.used, 1);
});

test('concurrent duplicate submissions reserve only one request', async () => {
  const f = fixture(), input = request();
  await Promise.all(Array.from({ length: 12 }, () => f.post(input)));
  assert.equal(f.repository.used, 1);
  assert.equal(f.calls.filter(c => c.init.method === 'POST').length, 1);
});

test('reusing an id with changed topic data is rejected', async () => {
  const f = fixture(), input = request();
  await f.post(input);
  assert.equal((await f.post({ ...input, title: 'Different topic' })).status, 409);
  assert.equal(f.repository.used, 1);
});

test('cover cap is independent and exhausted requests never call fal', async () => {
  const f = fixture({ repository: memoryRepository(2) });
  await Promise.all(Array.from({ length: 10 }, () => f.post(request())));
  assert.equal(f.repository.used, 2);
  assert.equal(f.calls.length, 2);
  assert.equal([...f.repository.jobs.values()].filter(j => j.status === 'limited').length, 8);
});

test('an explicitly unlimited cover quota retains usage and duplicate protection', async () => {
  const f = fixture({ repository: memoryRepository(null) });
  const inputs = Array.from({ length: 101 }, () => request());
  await Promise.all(inputs.map(input => f.post(input)));
  await f.post(inputs[0]);
  assert.equal(f.repository.used, 101);
  assert.equal(f.calls.filter(c => c.init.method === 'POST').length, 101);
  assert.equal([...f.repository.jobs.values()].filter(j => j.status === 'limited').length, 0);
});

test('an unknown submission outcome never retries paid work', async () => {
  let calls = 0;
  const f = fixture({ fetchFn: async () => { calls++; throw new Error('timeout after send'); } });
  const input = request();
  assert.equal((await (await f.post(input)).json()).status, 'uncertain');
  assert.equal((await (await f.post(input)).json()).status, 'uncertain');
  assert.equal((await (await f.app.request(`/covers/${input.id}`)).json()).status, 'uncertain');
  assert.equal(calls, 1);
});

test('stale reservations become uncertain instead of submitting again', async () => {
  const f = fixture({ now: () => Date.now() + 60_000 }), input = request();
  await f.post(input);
  const job = f.repository.jobs.get(input.id);
  f.repository.jobs.set(input.id, { ...job, status: 'submitting', providerID: null });
  const result = await (await f.post(input)).json();
  assert.equal(result.status, 'uncertain');
  assert.equal(f.calls.filter(c => c.init.method === 'POST').length, 1);
});

test('server rejects excess context and client-owned prompt/model fields', async () => {
  const f = fixture();
  for (const extra of [{ headlines: Array(7).fill('topic') }, { prompt: 'bypass style' },
    { model: 'other' }, { title: '' }, { styleVersion: 2 }, { id: 'wrong' }]) {
    assert.equal((await f.post(request(extra))).status, 400);
  }
  assert.equal(f.calls.length, 0);
});

test('provider URLs cannot turn status checks into arbitrary authenticated fetches', async () => {
  let calls = 0;
  const f = fixture({ fetchFn: async () => {
    calls++;
    return Response.json({ request_id: 'x', status_url: 'https://evil.example/status', response_url: 'https://evil.example/result' });
  } });
  assert.equal((await (await f.post(request())).json()).status, 'uncertain');
  assert.equal(calls, 1);
});

test('completed provider failures preserve a usable failed state', async () => {
  const f = fixture(), input = request();
  await f.post(input);
  const failApp = new Hono().route('/covers', coverRoutes({ key: 'key', repository: f.repository,
    fetchFn: async () => Response.json({ status: 'COMPLETED', error: 'moderated' }) }));
  assert.equal((await (await failApp.request(`/covers/${input.id}`)).json()).status, 'failed');
});

test('a 422 result is terminal and polling does not create a replacement', async () => {
  const f = fixture(), input = request();
  await f.post(input);
  let polls = 0;
  const failApp = new Hono().route('/covers', coverRoutes({ key: 'key', repository: f.repository,
    fetchFn: async url => {
      polls++;
      return url.endsWith('/status') ? Response.json({ status: 'COMPLETED' }) :
        Response.json({ error: 'moderated' }, { status: 422 });
    } }));
  assert.equal((await (await failApp.request(`/covers/${input.id}`)).json()).status, 'failed');
  assert.equal((await (await failApp.request(`/covers/${input.id}`)).json()).status, 'failed');
  assert.equal(polls, 2);
  assert.equal(f.repository.used, 1);
});

test('missing configuration does not spend or alter quota', async () => {
  const f = fixture({ key: undefined });
  assert.equal((await f.post(request())).status, 503);
  assert.equal(f.repository.used, 0);
});

test('malformed or unknown request IDs return bounded errors', async () => {
  const f = fixture();
  assert.equal((await f.app.request('/covers/no')).status, 400);
  assert.equal((await f.app.request(`/covers/${randomUUID()}`)).status, 404);
});

test('a warm database repository creates fresh deadlines after earlier queries expire', async t => {
  const controllers = [];
  t.mock.method(AbortSignal, 'timeout', () => {
    const controller = new AbortController();
    controllers.push(controller);
    return controller.signal;
  });
  const originalFetch = neonConfig.fetchFunction;
  neonConfig.fetchFunction = async (_url, options) => {
    assert.equal(options.signal.aborted, false);
    return Response.json({ fields: [], rows: [], rowCount: 0 });
  };
  try {
    const repository = coverDatabase('postgresql://test:test@db.example.com/test');
    for (const controller of controllers) controller.abort();
    assert.equal(await repository.get(randomUUID()), null);
    for (const controller of controllers) controller.abort();
    assert.equal(await repository.get(randomUUID()), null);
    assert.equal(controllers.length, 2);
  } finally { neonConfig.fetchFunction = originalFetch; }
});
