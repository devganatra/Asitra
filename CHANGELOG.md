# Changelog

All notable changes to Asitra are recorded here.

## Asitra rebrand — 2026-08-03

### Changed

- Renamed the product, Apple display name, web experience, AI assistant, shared contracts, release metadata, and documentation from Sakhya to Asitra.
- Adopted the tagline “Your everyday assistant.”
- Replaced the web favicon and social-sharing card with the Asitra identity.
- Retained legacy bundle, CloudKit, Keychain, preferences, and local-storage identifiers so existing accounts and data continue working after the rename.

## Beta 1 maintenance — 2026-08-03

### Fixed

- Natural-language dates and times now place timeline entries at the requested time.
- Reminder, shopping, and travel-list commands take priority over incidental food or movement words.
- Hiking, journal, and mindset phrases are classified consistently.
- Captured list items route to reminders, groceries, or travel lists and preserve due labels.
- Work-life totals now use recorded durations consistently.
- The floating Asitra assistant opens reliably and exposes its dialog state accessibly.
- Returning to Today after viewing a future reminder now resets the calendar to the current day.

## 0.1.0 Beta 1 — 2026-07-14

### Added

- A natural-language daily timeline for routines, work, expenses, fitness, food, habits, mindset, books, movies, journal entries, ideas, and notes.
- An always-open Quick Capture field with automatic category and destination suggestions.
- An elegant collapsible calendar for browsing previous days.
- Timeline-backed grocery, shopping, reminder, task, reading, and watching lists.
- Private lists and collaboration-ready shared lists with owner, editor, and viewer roles.
- Apple Reminders creation and completion synchronization.
- Apple Health workout and sleep import, including source attribution for compatible wearables such as WHOOP.
- Work-life balance, screen-time, expense, and activity summaries.
- Photo attachments and local persistence.
- Adaptive layouts for iPhone, iPad, and Mac.

### Known limitations

- Shared-list invitations and live collaboration require the production CloudKit container to be configured.
- Automatic per-app Screen Time requires Apple’s Family Controls entitlement and a Device Activity extension.
- Beta 1 stores the primary timeline locally until CloudKit synchronization is enabled.
