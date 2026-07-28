# Sakhya

A daily companion for iPhone, iPad, and Mac. Write naturally in one capture box and Sakhya organizes routines, work, purchases, exercise, meals, mindset, journal entries, ideas, books, movies, shopping lists, and reminders into one chronological timeline.

## Open and run

1. Open `AppleMobileApp.xcodeproj` in Xcode.
2. Select the `AppleMobileApp` scheme.
3. Choose a Mac, iPhone, or iPad destination and press Run.

Before installing on a physical device, select the app target and choose your Apple Developer team under **Signing & Capabilities**.

## Install Beta 1 on iPhone or iPad

The current beta is version **0.1.0 (1)**.

For your own device, connect the iPhone or iPad to the Mac, select it as the run destination in Xcode, choose your signing team, and press Run. For distribution to other people, archive the iOS app and upload it to TestFlight through Xcode Organizer. See [RELEASING.md](RELEASING.md) for the complete checklist.

## Current features

- “Today’s System” home dashboard with a current action, next actions, daily completion, process steps, and weekly system progress
- Customizable in-app widget canvas with drag-to-reorder, content-specific compact/standard/expanded designs, hide/restore, responsive iPhone stacking, and persistent layout
- Always-visible capture placed before the movable dashboard so manual, voice, and photo input remain immediate
- Persistent goals, personal systems, repeatable processes, scheduled actions, and morning/evening reviews
- Completing a system action writes evidence back to the daily timeline without creating an unrelated calendar event
- Natural-language smart capture with an editable category suggestion
- Voice notes with live speech transcription and timeline playback
- On-device photo interpretation for text, receipts, book covers, meals, and general image labels
- A floating private AI assistant for asking natural-language questions about personal statistics
- Eleven categories covering daily life, journaling, ideas, books, and movies
- Thirty days of realistic sample data across every major tracker, removable independently from personal entries
- Private iCloud/CloudKit synchronization for entries, lists, photos, and voice notes
- Recently Deleted with restore, permanent-delete, keep-iCloud, and delete-everywhere controls
- Expense amounts and fitness durations roll into automatic totals
- Dedicated beginner-friendly Money page with monthly spending plans, automatic everyday categories, savings goals with contribution history, and trip-budget tracking
- Expenses added from Money or a trip are written back to the shared timeline; savings contributions remain separate from spending totals
- Reading lists and movie watchlists with planned, in-progress, and completed states
- Seven-day spending, activity, food, habit, mindset, and journal analysis
- Work, personal, rest, and screen-time attribution by phone, tablet, Mac, web, or offline activity
- A seven-day work-life balance dashboard and guidance
- Checkable grocery, shopping, reminder, and task lists generated from natural input
- Local notifications for reminders with a detected or selected date and time
- Apple Health import for workouts and sleep, including source attribution for WHOOP, Apple Watch, and other Health-compatible apps
- One event pipeline: manual, app, and sensor entries share the same timeline and automatically update category trackers
- A lightweight tracker builder starts with Money, Books & Media, Habits, or Things, then offers focused templates such as novels, documentaries, saving goals, and reminders
- Tracker check-ins ask only for relevant details and write the result back to the shared timeline
- Reading and watching activity resolves into one list item with a current status and full timeline history
- Native Apple Reminders export with due dates, alerts, completion, and deletion synchronization
- Automatic Apple Calendar mirroring for every new personal entry, with exact detected time ranges and optional linked reminders
- “Tell me my today” assistant summaries combining the Sakhya timeline, due reminders, and connected Apple Calendar events
- Browse and add entries on previous dates
- Local persistence between launches, with an offline working copy on every device
- Adaptive navigation shared across all platforms
- Private and shared-list architecture with list-level ownership and edit or view-only permissions
- Custom lists that remain connected to Quick Capture and the daily timeline

## Architecture

- `AppEnvironment` is the composition root. It injects repositories, providers, and use cases instead of constructing infrastructure in views.
- `SystemFeatureModel` and `TodaySystemEngine` keep goals, systems, processes, actions, reviews, prioritization, and progress outside the compatibility coordinator.
- `AppModel` remains a temporary compatibility coordinator while feature state moves into `TimelineFeatureModel`, `CalendarFeatureModel`, and `HealthFeatureModel`.
- `TimelineRepository`, `ListRepository`, `CalendarRepository`, `HealthRepository`, and `SharedListRepository` isolate persistence and Apple-framework integrations.
- Typed SwiftData records are the offline source of truth. Records include revision, device, and modification metadata, and a durable outbox records unsynchronized mutations.
- CloudKit receives per-entry and per-list outbox mutations. The snapshot path is retained temporarily for incoming compatibility while record-level change-token fetching is completed.
- Shared lists use a private CloudKit root record and `CKShare`; CloudKit is initialized only when sharing is requested so unsigned local builds stay usable.
- `Packages/SakhyaContracts` is a local Swift package containing the stable AI and wearable integration contracts.
- On-device and remote AI providers, plus HTTP wearable providers, are replaceable adapters. Tokens are supplied at runtime and are never embedded in the app.
- `RootView` provides adaptive split navigation.
- `HomeView` is the daily timeline and entry flow.
- `LibraryView` presents insights and charts.

The deployment targets are iOS/iPadOS 17 and macOS 14.

## Data storage

- Entries, lists, and Recently Deleted metadata are stored in SwiftData under `Application Support/Sakhya/Database`.
- On the first SwiftData launch, legacy JSON records are copied from UserDefaults. The legacy copy is retained as a non-destructive migration fallback.
- Photos and voice notes are stored in the app's private `Application Support/Sakhya/Attachments` folder. Older `Dayline/Attachments` files remain readable and are not removed during migration.
- When iCloud sync is enabled, record-level mutations are sent from the durable outbox and the compatibility snapshot continues to carry metadata and attachment assets. Shared lists have dedicated CloudKit records and `CKShare` metadata.
- Settings → Data Management shows local usage and gives separate controls for sample data, Recently Deleted, clearing only this device, or deleting both the iCloud and local copies.

To activate CloudKit, select your Apple Developer team in Xcode, add the `iCloud.com.devganatra.sakhya` container to the App ID, and enable the iCloud/CloudKit capability for the target. Xcode will then attach the included platform entitlement configuration to the signed app. It is intentionally not attached to unsigned Mac builds, so the app continues to build and work locally before developer signing is configured.

## Platform integrations still requiring developer configuration

- Automatic per-app Screen Time needs Apple’s Family Controls distribution entitlement plus a Device Activity report extension.
- CloudKit synchronization code and entitlements are included; the Apple Developer team must create/assign the container before live sync can authenticate.

## Release automation

- Pull requests and release branches build the Mac and iOS Simulator variants in GitHub Actions.
- Tags such as `v0.1.0-beta.1` run release validation and create a GitHub prerelease.
- TestFlight uploads remain an explicit signed step in Xcode so Apple credentials are never stored in the repository.
