# Asitra Web

The responsive web companion for Asitra. It follows the same everyday structure as the native Apple app:

- **Today** — natural-language capture, voice dictation, photos, calendar strip, daily system, and editable timeline
- **Lists** — private lists and versioned shared lists with expiring one-time invite codes
- **Track** — health, habits, learning/media, and mindset check-ins
- **Money** — cash flow, personal surplus allocation, balance sheet/net worth, monthly spending, savings progress, trip planning, typed entry, natural Asitra commands, and reviewed PDF statement import
- **Balance** — work/personal context and cross-life signals
- **Ask Asitra** — one shared Terra-powered assistant for web, Mac, iPhone, and iPad

## Run locally

Node.js 22.13 or newer is required.

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Identity, data and privacy

The public web app supports independent Google and Apple sign-in through Better Auth. Provider access tokens are encrypted before D1 storage; sessions use secure, HTTP-only, SameSite cookies and are stored server-side. Existing platform-provided ChatGPT identities remain supported during migration. Every D1 query and R2 object key is scoped to the authenticated account. Matching verified Google and Apple accounts may be linked, while different emails are never merged automatically.

Structured records are stored in D1. Pictures (5 MB each), PDFs (10 MB) and voice notes (20 MB) are kept in a private R2 bucket with signature validation, a 250 MB per-account quota, upload throttling and ownership checks. Existing `localStorage` data is validated and copied to secure account storage; the old plaintext copy is removed only after the user confirms.

Settings provides a server-generated machine-readable export, validated import, up to 20 recent in-app recovery points, explicit AI-consent withdrawal and complete account deletion. Deletion includes D1 records, recovery versions, sessions, provider links and R2 objects. Account access is recovered through the connected Google or Apple identity; Asitra does not store a separate password.

Every state mutation requires same-origin authentication and a custom request header. State and shared-list writes use optimistic versions to detect concurrent edits. Backup and image imports enforce type, size, structure, and content-signature limits. Responses include a restrictive Content Security Policy, anti-framing, no-sniff, no-store, referrer, permissions, cross-origin, and HSTS protections.

Web data remains separate from Apple-only services. The signed native bridge currently carries only a bounded AI context; HealthKit, Screen Time, Apple Calendar, Apple Reminders, and CloudKit synchronization remain native-app integrations.

## Shared AI and grounded health context

The web and Apple clients call the same server-side AI service. Web and Apple users must explicitly enable AI analysis before any account context is sent. The consent decision and policy version are recorded in D1 and can be withdrawn. Requests are limited to 20 per hour on web and use OpenAI's `store: false` option. The default OpenAI API may retain abuse-monitoring logs for up to 30 days; Zero Data Retention requires separate OpenAI approval and configuration. Asitra calculates totals, durations, budget values, and balance scores before invoking the model. Those values are sent as `verifiedMetrics` with their source (for example, WHOOP via Apple Health), while recent timeline entries are supporting context. The model explains patterns but does not calculate authoritative health or financial values.

The native apps authenticate to `/api/native/session` with Sign in with Apple. The server verifies Apple's signature and audience, issues a random 30-day session, stores only its SHA-256 hash, and rate-limits native AI requests. The OpenAI API key never ships in an app or browser.

Production requires secrets in the hosted environment; never put them in committed `.env` files:

```text
BETTER_AUTH_SECRET=<at least 32 cryptographically random bytes>
ASITRA_PUBLIC_URL=https://asitra.app
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
APPLE_WEB_CLIENT_ID=...
APPLE_TEAM_ID=...
APPLE_KEY_ID=...
APPLE_PRIVATE_KEY_P8=...
OPENAI_API_KEY=...
APPLE_SIGN_IN_AUDIENCE=com.devganatra.sakhya
```

Register `https://asitra.app/api/auth/callback/google` with Google and `https://asitra.app/api/auth/callback/apple` with Apple. Apple web sign-in requires a Services ID associated with the native app and an HTTPS domain registered with Apple.

## Backup and recovery operations

- D1 Time Travel is always enabled on production D1 databases. The free Workers plan retains seven days and paid Workers retains 30 days. Before migrations, record a bookmark with `npx wrangler d1 time-travel info <database>`.
- A production restore is destructive. Put the app into maintenance mode, record the current bookmark, restore by timestamp/bookmark, run health and ownership tests, then reopen traffic. Keep the returned previous bookmark so the restore can be undone.
- R2 durability is not the same as user-error recovery. For public beta, export a private inventory and encrypted copy to a separate restricted bucket/account on a documented schedule. Do not apply automatic deletion to active uploads.
- Test recovery quarterly with non-production data and record recovery time and data-loss window. Restrict restore credentials to operators who need them.

## Use your own language model

AI access is behind a server-side provider boundary. To run a self-hosted model everywhere, expose it through a public HTTPS endpoint compatible with `POST /v1/chat/completions`, then configure:

```text
AI_PROVIDER=openai-compatible
CUSTOM_AI_BASE_URL=https://your-model-gateway.example
CUSTOM_AI_API_KEY=...
CUSTOM_AI_MODEL=your-model-id
```

Do not point the production service at localhost, a private IP, or an unauthenticated inference server. The gateway must provide authentication, encryption in transit, rate limits, monitoring, and an appropriate privacy policy. Changing this configuration switches the model for every Asitra client without an app update.

## Validate

```bash
npm test
```

See [LAUNCH_CHECKLIST.md](./LAUNCH_CHECKLIST.md) before changing production access.

The full user-facing policy is available at `/privacy`. Privacy language and processor agreements still require review by a qualified privacy professional before a broad commercial launch.

The production build targets the Sites Cloudflare Worker runtime through vinext.
