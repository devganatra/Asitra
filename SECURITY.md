# Asitra Security

Report suspected security or privacy issues privately to `ganatra.dev@gmail.com`. Do not include real journal, health, location, or financial records in the first message.

## Current controls

- Authenticated, account-isolated storage for web state and attachments
- Same-origin checks on mutations and explicit mutation headers
- Input, schema, file-type, file-signature, and request-size validation
- Versioned state and shared-list updates to prevent silent overwrites
- One-time, 20-character shared-list invite codes that expire after seven days
- Server-side AI credentials, explicit AI consent, no-store model requests, and hourly limits
- Private attachment reads, abandoned-upload cleanup, user export, and complete account deletion
- Security headers including CSP, HSTS, no-sniff, anti-framing, and restrictive browser permissions

## Operational requirements

- Keep production secrets only in the hosting environment.
- Enable platform logs and alerts for 5xx, 409, 429, and unusual attachment volume.
- Review dependencies before every release with `npm audit`.
- Restore-test database and object-storage backups before public launch and quarterly afterward.
- Rotate any credential immediately if it appears in source, logs, screenshots, or support messages.

No security control makes a service risk-free. Public access should remain a controlled beta until monitoring, restore tests, and privacy review are complete.
