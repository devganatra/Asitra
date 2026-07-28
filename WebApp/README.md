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

The current web version stores data in the browser with `localStorage`. Settings provides JSON export, import, and a confirmed sample-data reset.

Browser data is intentionally separate from Apple-only services. HealthKit, Screen Time, Apple Calendar, Apple Reminders, and CloudKit synchronization remain native-app integrations until a signed account bridge is added.

## Validate

```bash
npm test
```

The production build targets the Sites Cloudflare Worker runtime through vinext.
