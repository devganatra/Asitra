# Releasing Sakhya

Sakhya uses two related release channels:

1. GitHub prereleases preserve source history, release notes, and validation results.
2. TestFlight delivers signed beta builds that people can install on iPhone and iPad.

## Version convention

- Xcode marketing version: `0.1.0`
- Xcode build number: `1`, incremented for every App Store Connect upload
- Git tag: `v0.1.0-beta.1`

The marketing version must contain only numbers and periods. The beta label belongs in the Git tag and TestFlight metadata.

## GitHub beta release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Update `CHANGELOG.md`.
3. Open and merge the release pull request.
4. Tag the merged commit and push the tag:

   ```bash
   git tag -a v0.1.0-beta.1 -m "Sakhya 0.1.0 Beta 1"
   git push origin v0.1.0-beta.1
   ```

The release workflow verifies Mac and iOS Simulator builds before creating a GitHub prerelease.

## Install directly on your own iPhone or iPad

1. Install the iOS platform from Xcode > Settings > Components.
2. Sign in under Xcode > Settings > Accounts.
3. Connect and trust the device.
4. Open `AppleMobileApp.xcodeproj`.
5. Select the Sakhya target and choose your team under Signing & Capabilities.
6. Confirm that `com.devganatra.sakhya` is available to the team. Change it to another unique reverse-domain identifier if needed.
7. Select the connected device and press Run.

This route is suitable for development. TestFlight is the better route for repeatable beta installation and updates.

## Upload Beta 1 to TestFlight

Prerequisites:

- Active Apple Developer Program membership
- An App Store Connect app record using the same bundle ID
- Agreements accepted in App Store Connect
- Apple Health capability enabled for the App ID
- A Mac with the matching iOS platform installed in Xcode

Steps:

1. In Xcode, select the Sakhya scheme and **Any iOS Device (arm64)**.
2. Choose Product > Archive.
3. In Organizer, select the archive and click Distribute App.
4. Choose **TestFlight & App Store** or **TestFlight Internal Only**.
5. Keep automatic signing and symbol upload enabled, then upload.
6. In App Store Connect > Sakhya > TestFlight, wait for processing.
7. Add Beta 1 to an internal testing group and enter the following What to Test text:

   > Test Quick Capture, the calendar, private and shared-list setup, reminders, Health import, and timeline-to-tracker updates. Shared-list live invitations are not enabled in this build.

8. Install Apple’s TestFlight app on the iPhone or iPad and accept the tester invitation.

Never commit signing certificates, provisioning profiles, App Store Connect private keys, or passwords to this repository.
