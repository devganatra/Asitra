# Web public-beta checklist

## Automated gates

- `npm ci`
- `npm run lint`
- `npm test`
- `npm audit --omit=dev`
- macOS and iOS Simulator builds with signing disabled

## Hosting

- The repository-root build delegates to `WebApp` and copies its verified vinext output to `dist` for Sites monorepo deployment.
- Apply all D1 migrations before deploying application code.
- Confirm the D1 database and private R2 bucket are bound.
- Generate `BETTER_AUTH_SECRET` with at least 32 random bytes and store it only as a hosting secret.
- Configure `ASITRA_PUBLIC_URL`, Google OAuth credentials, and the exact Google callback URL.
- Configure an Apple Services ID, Team ID, Key ID and `.p8` private key, plus the exact Apple callback URL.
- Set `APPLE_SIGN_IN_AUDIENCE` to the production bundle identifier.
- Keep `OPENAI_API_KEY` unset for a no-cost local-insights beta, or set it only after usage alerts and a monthly budget are configured.
- Verify `/api/health`, Google sign-in, Apple sign-in, logout, account isolation, state load/save, recovery, export, complete deletion, R2 ownership, shared-list join/update, and AI consent on web and Apple.
- Confirm the OpenAI key exists only in the server secret store and rotate any key ever placed in a client, log or Git history.
- Confirm OAuth tokens are encrypted, production cookies are Secure/HTTP-only/SameSite, and rate-limit tables are receiving events.

## Backup and incident readiness

- Verify D1 reports `version: production` and record a Time Travel bookmark before each migration.
- Document maintenance mode and D1 restore commands; rehearse a restore with non-production data.
- Keep a separately restricted R2 backup/inventory plan and test restoring a sample picture, PDF and voice note.
- Restrict Cloudflare, Google, Apple and OpenAI administrative roles; require MFA and keep two recovery administrators.
- Store provider recovery codes outside the repository and test account recovery before inviting users.
- Create key-rotation and breach-notification runbooks with named owners and contact paths.

## GDPR readiness

- Review `/privacy` with qualified counsel and sign required processor/data-processing agreements.
- Verify the controller identity, support address, retention periods, international-transfer wording and age policy.
- Test download-my-data, AI-consent withdrawal and delete-my-data as a normal user.
- Maintain a processing register and an auditable process for access, correction, erasure and regulator requests.

## Controlled launch

1. Keep custom access and invite the first three to five testers.
2. Observe errors, storage volume, state conflicts, and AI rate limits for at least 48 hours.
3. Confirm privacy wording and support contact.
4. Change access to public only after the controlled test passes.
5. Keep a rollback target pointing to the previous known-good deployment.

## Known platform boundary

The web application is fully usable without Apple Health, Calendar, Reminders, or Screen Time. Those capabilities remain native-only until a user-approved identity-linking flow connects the Apple account to the same Asitra web account. Do not describe the stores as synchronized before that flow ships.
