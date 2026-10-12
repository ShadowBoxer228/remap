# ReMap gateway

**A small authenticated boundary between the iPad and cloud AI.**

Hono on Node.js 24 and Vercel. The gateway owns provider credentials, installation
enrollment, model instructions, request validation and usage accounting. The native
client owns local documents and atomic map edits.

## Local setup

```sh
cd backend
npm ci
cp .env.example .env.local
npm test
```

Fill `.env.local` with credentials for **your own** services. Never commit it.
Install the Vercel CLI to use `npm run dev` or deploy the gateway.

| Variable | Purpose |
| :--- | :--- |
| `OPENAI_API_KEY` | Server-side OpenAI credential |
| `REMAP_ACCESS_TOKEN` | Development gateway credential; at least 32 characters |
| `DATABASE_URL` | Postgres connection for usage, access and cover jobs |
| `FAL_KEY` | Optional topic-cover generation credential |
| `REMAP_ENROLLMENT_SECRET` | Private installation-token signing secret |

Review [schema.sql](schema.sql), [enrollment-schema.sql](enrollment-schema.sql) and
[covers-schema.sql](covers-schema.sql) before initializing your database.
[unlimited-usage.sql](unlimited-usage.sql) is an **optional policy change** that removes
lifetime count limits; do not apply it blindly. Rate controls are not a dollar budget.

For an independently signed DEBUG app, the root
[prepare_internal_library.py](../tools/prepare_internal_library.py) helper provisions
a selected app data container with **your own HTTPS endpoint and token file**.
Run it with `--help`. It does not start a simulator or put credentials in the binary.
Cloning the app does not grant access to the maintainer's hosted service.

## Routes

Service routes require a credential via `Authorization: Bearer …` or `X-ReMap-Token`,
except public health and the separately verified enrollment exchange.

| Route | Responsibility |
| :--- | :--- |
| `GET /health` | Configuration presence; not full provider health |
| `POST /access/enroll` | Verify an Apple installation proof and issue access |
| `POST /coach` | Structured review and map conversation |
| `POST /realtime/token` | Temporary access for the legacy voice path |
| `POST /api/native/headlines` | Generate 6–24 PDF topics with verified page anchors |
| `POST /api/native/coach` | Source-grounded text coaching |
| `POST /api/native/realtime/token` | Source-aware live voice and tool definitions |
| `POST /api/native/command` | Validate a requested map command |
| `POST /covers` · `GET /covers/:id` | Submit and inspect optional cover jobs |

PDFKit extracts text and Vision OCR handles scanned pages on the iPad. Native
requests carry bounded excerpts and, when relevant, a map image and a bounded PDF page image to preserve table layout. Original PDFs
remain on the device. Source lookup and citation validation use the current
session's document; a model-provided page number is not trusted by itself.

## Security boundaries

- Provider keys stay in the backend. The app gets an installation credential or
  a short-lived voice credential, never the provider key.
- Enrollment verifies Apple's certificate chain, signature, expected bundle and
  supported environment. It is configured for **internal TestFlight / Sandbox**,
  not general public production enrollment.
- Authentication precedes native inference routes. Body limits, bounded context,
  usage reservations and validation constrain input.
- Map commands require explicit intent and a current revision. Server validation
  is followed by native validation; malformed output must not partially edit a map.
- Access records store pseudonymous identifiers and token hashes. Postgres does
  not store complete PDFs, map content or audio.
- Logs use operational error codes. Do not add credentials, prompts or audio.

Apple root certificates in `certificates/` are public trust anchors, not signing
keys. Test credentials are synthetic fixtures.

## Tests and deployment

`npm test` runs protocol tests without live paid provider calls. Live qualification
is a separate, explicitly scoped operation. Deploy only to a project you control:

```sh
vercel link
vercel env add OPENAI_API_KEY
# Configure the remaining required variables in the selected project.
vercel deploy --prod
```

Check the selected project and provider budgets before deployment. Protocol tests,
an archive and an upload receipt do not establish fresh-install enrollment on a
real iPad. See [architecture](../docs/ARCHITECTURE.md),
[privacy](../docs/PRIVACY.md) and [security](../SECURITY.md).
