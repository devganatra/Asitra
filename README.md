# Dayline

A daily everything-log for iPhone, iPad, and Mac. Write naturally in one capture box and Dayline organizes routines, work, purchases, exercise, meals, mindset, journal entries, ideas, books, and movies into one chronological timeline.

## Open and run

1. Open `AppleMobileApp.xcodeproj` in Xcode.
2. Select the `AppleMobileApp` scheme.
3. Choose a Mac, iPhone, or iPad destination and press Run.

Before installing on a physical device, select the app target and choose your Apple Developer team under **Signing & Capabilities**.

## Current features

- Natural-language smart capture with an editable category suggestion
- Eleven categories covering daily life, journaling, ideas, books, and movies
- Photo attachments stored as local files
- Expense amounts and fitness durations roll into automatic totals
- Reading lists and movie watchlists with planned, in-progress, and completed states
- Seven-day spending, activity, food, habit, mindset, and journal analysis
- Work, personal, rest, and screen-time attribution by phone, tablet, Mac, web, or offline activity
- A seven-day work-life balance dashboard and guidance
- Browse and add entries on previous dates
- Local persistence between launches
- Adaptive navigation shared across all platforms

## Architecture

- `AppModel` owns the timeline and local persistence.
- `RootView` provides adaptive split navigation.
- `HomeView` is the daily timeline and entry flow.
- `LibraryView` presents insights and charts.

The deployment targets are iOS/iPadOS 17 and macOS 14.

## Platform integrations still requiring developer configuration

- Automatic per-app Screen Time needs Apple’s Family Controls distribution entitlement plus a Device Activity report extension.
- Cross-device data and photo synchronization needs a private CloudKit container, signing team, and migration from local persistence.
