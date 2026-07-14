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

- Natural-language smart capture with an editable category suggestion
- Eleven categories covering daily life, journaling, ideas, books, and movies
- Photo attachments stored as local files
- Expense amounts and fitness durations roll into automatic totals
- Reading lists and movie watchlists with planned, in-progress, and completed states
- Seven-day spending, activity, food, habit, mindset, and journal analysis
- Work, personal, rest, and screen-time attribution by phone, tablet, Mac, web, or offline activity
- A seven-day work-life balance dashboard and guidance
- Checkable grocery, shopping, reminder, and task lists generated from natural input
- Local notifications for reminders with a detected or selected date and time
- Apple Health import for workouts and sleep, including source attribution for WHOOP, Apple Watch, and other Health-compatible apps
- One event pipeline: manual, app, and sensor entries share the same timeline and automatically update category trackers
- Reading and watching activity resolves into one list item with a current status and full timeline history
- Native Apple Reminders export with due dates, alerts, completion, and deletion synchronization
- Browse and add entries on previous dates
- Local persistence between launches
- Adaptive navigation shared across all platforms
- Private and shared-list architecture with list-level ownership and edit or view-only permissions
- Custom lists that remain connected to Quick Capture and the daily timeline

## Architecture

- `AppModel` owns the timeline and local persistence.
- `RootView` provides adaptive split navigation.
- `HomeView` is the daily timeline and entry flow.
- `LibraryView` presents insights and charts.

The deployment targets are iOS/iPadOS 17 and macOS 14.

## Platform integrations still requiring developer configuration

- Automatic per-app Screen Time needs Apple’s Family Controls distribution entitlement plus a Device Activity report extension.
- Cross-device data and photo synchronization needs a private CloudKit container, signing team, and migration from local persistence.

## Release automation

- Pull requests and release branches build the Mac and iOS Simulator variants in GitHub Actions.
- Tags such as `v0.1.0-beta.1` run release validation and create a GitHub prerelease.
- TestFlight uploads remain an explicit signed step in Xcode so Apple credentials are never stored in the repository.
