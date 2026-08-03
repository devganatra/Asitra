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
- Set `APPLE_SIGN_IN_AUDIENCE` to the production bundle identifier.
- Keep `OPENAI_API_KEY` unset for a no-cost local-insights beta, or set it only after usage alerts and a monthly budget are configured.
- Verify `/api/health`, authenticated state load/save, export, account deletion, image ownership, shared-list join/update, and AI consent.

## Controlled launch

1. Keep custom access and invite the first three to five testers.
2. Observe errors, storage volume, state conflicts, and AI rate limits for at least 48 hours.
3. Confirm privacy wording and support contact.
4. Change access to public only after the controlled test passes.
5. Keep a rollback target pointing to the previous known-good deployment.

## Known platform boundary

The web application is fully usable without Apple Health, Calendar, Reminders, or Screen Time. Those capabilities remain native-only until a user-approved identity-linking flow connects the Apple account to the same Sakhya web account. Do not describe the stores as synchronized before that flow ships.
