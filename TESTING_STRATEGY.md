# Sakhya cross-platform testing strategy

Sakhya uses one product contract across web, macOS, iPhone, and iPad. A change is releasable only when its shared contract, platform implementation, user flow, privacy behavior, and production deployment all pass the relevant gates below.

## Release gates

| Gate | What it protects | Required checks |
| --- | --- | --- |
| Shared contracts | Web and Apple interpret the same data and AI responses | TypeScript contract tests, Swift package tests, both AI routes using the same server service |
| Domain behavior | Natural capture, money import, lists, reminders, and timelines | Deterministic parser and data tests with boundary dates, currencies, and malformed input |
| Web integration | Authentication, storage, headers, rate limits, consent, and APIs | Local Worker integration tests against the production build |
| Apple integration | Swift compilation and Apple framework wiring | Swift package tests plus unsigned macOS and iOS Simulator release builds |
| User journeys | Real usability rather than component success | Keyboard, pointer, phone-width, and native Mac smoke flows using realistic daily data |
| Production | The deployed artifact matches the tested commit | Versioned deployment, health/config checks, and a final browser smoke test |

## One AI model contract

`WebApp/app/ai-contract.ts` is the default model source of truth. Both `/api/assistant` and `/api/native/assistant` call `answerWithSakhyaAI`, so web and Apple cannot select different OpenAI models. The public, secret-free `/api/assistant/config` response lets every client display the model actually selected by the backend. Apple decodes that response through `SakhyaContracts`; it does not contain its own model identifier.

The default is the balanced `gpt-5.6-terra` tier with low reasoning. A custom compatible gateway may override the backend model, but the override applies to both clients and is returned through the same contract endpoint. API keys remain server-only.

## Automated matrix

Run before every pull request and release:

```sh
npm test
npm run lint
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test --package-path Packages/SakhyaContracts
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AppleMobileApp.xcodeproj -scheme AppleMobileApp -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AppleMobileApp.xcodeproj -scheme AppleMobileApp -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The GitHub Actions workflow repeats the Apple builds on a clean macOS runner. Local failures caused by a missing Xcode platform must be reported as environment blockers; they are not application test failures.

## Critical user journeys

1. Capture a natural-language event with date, time, duration, place, and reminder; verify the preview before writing Apple Calendar or Reminders.
2. Add expense, income, saving, and investment records through direct entry, Sakhya text, and statement import; reconcile cash flow and unallocated surplus.
3. Create private and shared lists, update an item from the timeline, and verify both surfaces remain consistent.
4. Import fitness/sleep data, preserve its source, and ask the assistant for a grounded summary without allowing it to invent calculations.
5. Edit and delete timeline entries, test Recently Deleted, export data, and verify no destructive action occurs without confirmation.
6. Ask the same grounded question on web and Apple; verify both responses report the same model, profile, and contract version.

## Test data and privacy

Use synthetic accounts and synthetic health, finance, travel, and journal data in automated and production smoke tests. Never place real API keys, Apple tokens, health records, payment details, or exported user data in fixtures, screenshots, logs, or source control. Production smoke tests should avoid permanent writes unless the test account is explicitly disposable.
