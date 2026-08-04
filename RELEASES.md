# Asitra release history

This ledger is the source of truth for what changed, where it was developed, and which pull request delivered it. Every feature release must add a new entry and update `release.json`.

## 0.2.0-beta.7 — 2026-08-04

- Branch: `codex/dynamic-ui`
- Pull request: [#43](https://github.com/devganatra/Asitra/pull/43)
- Platforms: Web, macOS, iOS, iPadOS
- Changes:
  - Redesigned Today as a more adaptive daily workspace with clearer progress and focus.
  - Made tasks draggable between priority quadrants and progress columns.
  - Added direct movement controls for touch and keyboard use.
  - Kept every task anchored to its original list while synchronizing completion and timeline state.

## 0.2.0-beta.6 — 2026-08-04

- Branch: `codex/release-tracking`
- Pull request: [#42](https://github.com/devganatra/Asitra/pull/42)
- Platforms: Web, macOS, iOS, iPadOS
- Changes:
  - Added one canonical release manifest shared by every platform.
  - Added an automated pull-request guard that rejects feature work without a version bump and release-history entry.
  - Synchronized the Apple marketing/build versions with the web release.

## 0.2.0-beta.5 — 2026-08-04

- Branch: `codex/auto-dismiss-notices`
- Pull request: [#41](https://github.com/devganatra/Asitra/pull/41)
- Platforms: Web
- Changes:
  - Made confirmation messages dismiss themselves after four seconds.
  - Preserved manual dismissal and restarted the timer for repeated messages.

## 0.2.0-beta.4 — 2026-08-04

- Branch: `codex/universal-entry-model`
- Pull request: [#39](https://github.com/devganatra/Asitra/pull/39)
- Platforms: Web, macOS, iOS, iPadOS
- Changes:
  - Introduced the universal entry capability model across web and Apple.

- Follow-up branch: `codex/task-matrix-board`
- Follow-up pull request: [#40](https://github.com/devganatra/Asitra/pull/40)
- Historical note: the Tasks matrix and editable board were added without a release bump. The new release guard prevents this gap from recurring.

## 0.2.0-beta.3 — 2026-08-04

- Branch: `codex/trip-planning`
- Pull request: [#38](https://github.com/devganatra/Asitra/pull/38)
- Platforms: Web, macOS, iOS, iPadOS
- Changes:
  - Completed trip planning and its cross-platform flow.

## 0.2.0-beta.2 — 2026-08-04

- Branches: `codex/finite-day-money-mindset`, `codex/custom-money-cycle`, `codex/stabilize-web-integration`
- Pull requests: [#34](https://github.com/devganatra/Asitra/pull/34), [#35](https://github.com/devganatra/Asitra/pull/35), [#36](https://github.com/devganatra/Asitra/pull/36), [#37](https://github.com/devganatra/Asitra/pull/37)
- Platforms: Web, macOS, iOS, iPadOS
- Changes:
  - Added finite-day planning, unified personal-finance views, salary-aligned money cycles, and stable web integration storage.

## 0.2.0-beta.1 — 2026-08-03

- Branch: `codex/release-visibility`
- Pull request: [#33](https://github.com/devganatra/Asitra/pull/33)
- Platforms: Web
- Changes:
  - Added a visible, traceable release number to the web application.
