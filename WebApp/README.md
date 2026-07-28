# Sakhya Web

The responsive web companion for Sakhya. It follows the same everyday structure as the native Apple app:

- **Today** — natural-language capture, voice dictation, photos, calendar strip, daily system, and editable timeline
- **Lists** — private and shared-list flows with timeline-connected items
- **Track** — health, habits, learning/media, and mindset check-ins
- **Money** — monthly spending, savings progress, and trip planning
- **Balance** — work/personal context and cross-life signals
- **Ask Sakhya** — a conversational interface that answers from the data saved in the browser

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

Web data remains separate from Apple-only services. HealthKit, Screen Time, Apple Calendar, Apple Reminders, and CloudKit synchronization remain native-app integrations until a signed account bridge is added.

## Validate

```bash
npm test
```

The production build targets the Sites Cloudflare Worker runtime through vinext.
