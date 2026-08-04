# Releasing Asitra

Asitra uses two related release channels:

1. GitHub prereleases preserve source history, release notes, and validation results.
2. TestFlight delivers signed beta builds that people can install on iPhone and iPad.

## Version convention

- Canonical release: `release.json`
- Xcode marketing version: `0.2.0`
- Xcode build number: the beta number, for example `6` for beta.6
- Web and repository version: `0.2.0-beta.6`
- Git tag: `v0.2.0-beta.6`

The marketing version must contain only numbers and periods. The beta label belongs in the Git tag and TestFlight metadata.

## Feature branch release workflow

Every user-visible feature gets its own beta number and trace entry:

1. Create a `codex/...` branch from `main`.
2. Set the next beta before opening the pull request:

   ```bash
   npm run release:set -- 0.2.0-beta.7
   ```

3. Add an entry to `RELEASES.md` with the release, date, branch, pull request, platforms, and user-visible changes.
4. Run `npm run release:check` and the platform tests.
5. Merge only after the **Release number and branch history** check passes.

The release check blocks product changes when the version did not advance or the current branch and pull request are absent from the release ledger.

## GitHub beta release

1. Run `npm run release:set -- <version>`.
2. Update `RELEASES.md`.
3. Open and merge the release pull request.
4. Tag the merged commit and push the tag:

   ```bash
   git tag -a v0.2.0-beta.6 -m "Asitra 0.2.0 Beta 6"
   git push origin v0.2.0-beta.6
   ```

The release workflow verifies Mac and iOS Simulator builds before creating a GitHub prerelease.

## Install directly on your own iPhone or iPad

1. Install the iOS platform from Xcode > Settings > Components.
2. Sign in under Xcode > Settings > Accounts.
3. Connect and trust the device.
4. Open `AppleMobileApp.xcodeproj`.
5. Select the `AppleMobileApp` target (display name: Asitra) and choose your team under Signing & Capabilities.
6. Confirm that the existing `com.devganatra.sakhya` bundle identifier belongs to the team. It is retained so the rebrand remains an update of the same application rather than creating a second app.
7. Select the connected device and press Run.

This route is suitable for development. TestFlight is the better route for repeatable beta installation and updates.

## Upload a beta to TestFlight

Prerequisites:

- Active Apple Developer Program membership
- An App Store Connect app record using the same bundle ID
- Agreements accepted in App Store Connect
- Apple Health capability enabled for the App ID
- A Mac with the matching iOS platform installed in Xcode

Steps:

1. In Xcode, select the `AppleMobileApp` scheme and **Any iOS Device (arm64)**.
2. Choose Product > Archive.
3. In Organizer, select the archive and click Distribute App.
4. Choose **TestFlight & App Store** or **TestFlight Internal Only**.
5. Keep automatic signing and symbol upload enabled, then upload.
6. In App Store Connect > Asitra > TestFlight, wait for processing.
7. Add the beta to an internal testing group and enter the following What to Test text:

   > Test Quick Capture, the calendar, private and shared-list setup, reminders, Health import, and timeline-to-tracker updates. Shared-list live invitations are not enabled in this build.

8. Install Apple’s TestFlight app on the iPhone or iPad and accept the tester invitation.

Never commit signing certificates, provisioning profiles, App Store Connect private keys, or passwords to this repository.
