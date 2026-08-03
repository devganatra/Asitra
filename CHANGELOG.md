# Changelog

All notable changes to Sakhya are recorded here.

## Beta 1 maintenance — 2026-08-03

### Fixed

- Natural-language dates and times now place timeline entries at the requested time.
- Reminder, shopping, and travel-list commands take priority over incidental food or movement words.
- Hiking, journal, and mindset phrases are classified consistently.
- Captured list items route to reminders, groceries, or travel lists and preserve due labels.
- Work-life totals now use recorded durations consistently.
- The floating Sakhya assistant opens reliably and exposes its dialog state accessibly.

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
