# Task 3 Report — Independent consent and functional configuration

## RED

- Added focused tests for independent polish consent, v1 settings decoding, shared-secret preservation, loopback/no-Keychain dispatch, and local-only short-circuiting.
- `xcodebuild` with `/tmp/tsb-polish-task3-red` failed as expected because polish fields, revocation, and dispatch were absent.

## GREEN

- Added default-off polish settings with `decodeIfPresent` compatibility while retaining `organization-settings.v1`.
- Added independent polish eligibility, shared endpoint-bound Keychain retention, local-only `.notEligible` fallback, a separate consent sheet, and local terminology editor using `canonical = alias1 | alias2`.
- Focused command (with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`) passed 38 tests: `OrganizationSettingsStoreTests`, `SettingsBehaviorTests`, and `SettingsSourceTests`.

## Files

- `TSB/Core/Settings/OrganizationSettings.swift`
- `TSB/Core/Settings/OrganizationSettingsStore.swift`
- `TSB/App/AppController.swift`
- `TSB/Views/SettingsView.swift`
- focused settings tests

## Self-review / concerns

- `git diff --check` is clean.
- No coordinator, network, or audio paths changed.
- Default signing failed on an unrelated copied third-party framework; the validated focused run disables signing only.

## Commit

- `feat(v0.2): authorize transcript polish independently` (current HEAD)
