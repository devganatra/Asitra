# Sakhya Web

The responsive web companion for Sakhya. It follows the same everyday structure as the native Apple app:

- **Today** — natural-language capture, voice dictation, photos, calendar strip, daily system, and editable timeline
- **Lists** — private and shared-list flows with timeline-connected items
- **Track** — health, habits, learning/media, and mindset check-ins
- **Money** — cash flow, personal surplus allocation, balance sheet/net worth, monthly spending, savings progress, trip planning, typed entry, natural Sakhya commands, and reviewed PDF statement import
- **Balance** — work/personal context and cross-life signals
- **Ask Sakhya** — one shared Terra-powered assistant for web, Mac, iPhone, and iPad

## Run locally

Node.js 22.13 or newer is required.

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Data and privacy

The web app requires the platform-provided ChatGPT sign-in. Structured data is stored in D1 under a one-way hash of the signed-in email, and images are kept in a private R2 bucket with account ownership checks. Existing `localStorage` data is validated and copied to secure account storage; the old plaintext copy is removed only after the user confirms. Settings provides validated JSON export, import, and a confirmed sample-data reset.

Every state mutation requires same-origin authentication and a custom request header. Backup and image imports enforce type, size, structure, and content-signature limits. Responses include a restrictive Content Security Policy, anti-framing, no-sniff, no-store, referrer, permissions, cross-origin, and HSTS protections.

Web data remains separate from Apple-only services. The signed native bridge currently carries only a bounded AI context; HealthKit, Screen Time, Apple Calendar, Apple Reminders, and CloudKit synchronization remain native-app integrations.

## Shared AI and grounded health context

The web and Apple clients call the same server-side AI service. Sakhya calculates totals, durations, budget values, and balance scores before invoking the model. Those values are sent as `verifiedMetrics` with their source (for example, WHOOP via Apple Health), while recent timeline entries are supporting context. The model explains patterns but does not calculate authoritative health or financial values.

The native apps authenticate to `/api/native/session` with Sign in with Apple. The server verifies Apple's signature and audience, issues a random 30-day session, stores only its SHA-256 hash, and rate-limits native AI requests. The OpenAI API key never ships in an app or browser.

Production requires `OPENAI_API_KEY` and `APPLE_SIGN_IN_AUDIENCE` in the hosted environment. The latter should remain `com.devganatra.sakhya` unless the bundle identifier changes.

## Use your own language model

AI access is behind a server-side provider boundary. To run a self-hosted model everywhere, expose it through a public HTTPS endpoint compatible with `POST /v1/chat/completions`, then configure:

```text
AI_PROVIDER=openai-compatible
CUSTOM_AI_BASE_URL=https://your-model-gateway.example
CUSTOM_AI_API_KEY=...
CUSTOM_AI_MODEL=your-model-id
```

Do not point the production service at localhost, a private IP, or an unauthenticated inference server. The gateway must provide authentication, encryption in transit, rate limits, monitoring, and an appropriate privacy policy. Changing this configuration switches the model for every Sakhya client without an app update.

## Validate

```bash
npm test
```

The production build targets the Sites Cloudflare Worker runtime through vinext.
