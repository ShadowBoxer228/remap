# ReMap private Realtime gateway

Hono on Vercel Node 24. Deployed project: `remap-coach` in
`dotsaround1-1553s-projects`. Production origin:
`https://remap-coach.vercel.app`.

Production environment variables:

- `OPENAI_API_KEY`: private OpenAI project key, stored only in Vercel.
- `REMAP_ACCESS_TOKEN`: long random credential shared privately with internal testers.
- `DATABASE_URL`: isolated Neon database for atomic quota counters and cover jobs.
- `FAL_KEY`: optional fal.ai credential for topic covers, stored only in Vercel.

The iPad sends `X-ReMap-Token`. `/health` is public and reports configuration
presence, not provider availability. All routes return `Cache-Control: no-store`.

- `POST /coach`: `{operation: "question"|"judge"|"conversation", context: "JSON string"}`.
  Model/prompts/tools are server-owned; question/judge output is limited to 160 tokens,
  conversation to 700. Uses one short Realtime WebSocket, with no automatic retry.
  Conversation context is allowlisted: latest message, 10 recent messages, up to
  60 nodes/80 edges, revision/selection, phase, bounded rule findings and truncation.
  A separate review_answer field routes actual review answers to existing validation.
- `POST /realtime/token`: `{}` selects legacy manual-turn voice;
  `{profile:"conversation"}` selects semantic VAD with automatic responses disabled.
  Returns only a 60-second `ek_` secret, expiry and model, never the primary key.
  Both use PCM24k, Marin and `gpt-4o-mini-transcribe`. The conversation profile has
  `apply_map_command` and `submit_review_answer`; the client validates atomic revision-checked
  transactions. Native conversation responses use a 500-token limit.
- `POST /covers` and `GET /covers/:id`: authenticated durable fal cover jobs.
  See `covers-schema.sql`. These routes are deployed but need FAL_KEY before real generation. Missing configuration
  fails closed; no automatic paid retry follows an uncertain submission.

The overall body limit is 32 KiB; covers further limit bodies to 8 KiB.

Neon `coach_quota` starts with 200 text calls and 10 voice-token issuances globally,
plus 12 calls per minute per kind. One conditional SQL UPDATE reserves usage across
concurrent Vercel instances. Upstream failures still consume a reservation. Caps
persist across deployments; there is no automatic reset. `schema.sql` is safe to
apply to this new isolated database and preserves existing counter values.

This is for trusted internal testers. Shared credentials are revocable but not
per-user authentication. An ephemeral bearer secret can configure its own Realtime
session; issuance caps and app time limits are **not a dollar spend ceiling**.
Before public launch add per-user auth, abuse controls, provider budget controls
and server-enforced voice session lifecycle. Do not raise quotas silently.

```sh
npm ci
npm test
vercel project inspect --non-interactive
vercel deploy --prod --yes --scope dotsaround1-1553s-projects
```

Verify the resolved project before deployment. Vercel must be redeployed after
changing environment variables. Never commit `.env*`, `.vercel/`, database URLs,
keys or tester tokens. `.env.example` lists names only. Logs contain operational
error codes, not prompts, audio or secrets. Vercel may retain normal request metadata.

Validated on 2026-10-12 against the real deployed API: authentication, health,
Socratic question, correct/incorrect calcium explanations, layout-only rejection,
temporary secret, PCM speech generation, transcription loopback, semantic VAD,
conversation explanation/command separation, response cancellation/truncation, and
voice tool-result acknowledgement. Reports are
under the root's ignored `build/QA/core-*`. Loopback is synthetic and does not prove
physical iPad microphone/speaker performance.

Official protocol references:

- https://developers.openai.com/api/docs/guides/realtime-conversations
- https://developers.openai.com/api/reference/resources/realtime/client-events
- https://developers.openai.com/api/reference/resources/realtime/subresources/client_secrets/methods/create
