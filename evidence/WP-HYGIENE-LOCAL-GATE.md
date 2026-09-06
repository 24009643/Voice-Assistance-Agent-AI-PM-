# WP-HYGIENE local-gate evidence

- Date: 2026-09-06, Asia/Shanghai
- Target host: Apple silicon, arm64, macOS 26.5.2 (25F84)
- Tested toolchain: Xcode 26.6 (17F113), Swift 6.3.3, XcodeGen 2.46.0
- Scope: bounded local repository, test and unsigned Debug-build evidence; no
  raw logs, generated project, model, audio or private user data is tracked
- Linked raw artifact hash: N/A. Raw Xcode/generated logs were intentionally
  not retained or tracked; reproduction is bounded by the tested commit and
  command.

## Expected result

An accepted full gate exits 0 with Python 5/5, SenseVoice 7/7, Paraformer
11/11, app XCTest 395/395, a successful independent unsigned Debug build and
temporary-directory cleanup. The strengthened ownership test passes 100/100;
documentation-tree checks exit 0 without tracked private or generated data.

## Actual results

| Tested commit | Reproduction command | Actual result |
|---|---|---|
| `593a058` | `/bin/sh scripts/verify-tsb.sh` twice consecutively | Both runs passed on the same head: Python 5/5, SenseVoice 7/7, Paraformer 11/11, app XCTest 395/395 and independent unsigned Debug build. Both crossed the former Keychain wait and cleaned their temporary directories. |
| `056d120` | `/bin/sh scripts/verify-tsb.sh` | One locked run passed with the same 5/5, 7/7, 11/11 and 395/395 counts plus independent Debug build. A later same-head run exited 65 only at the scheduler-dependent ownership test. |
| `21dcb32` | Focused command below with `ITERATIONS=100`, then `/bin/sh scripts/verify-tsb.sh` | Real source passed focused 100/100; the full locked gate passed 5/5, 7/7, 11/11 and 395/395 plus independent Debug build. |

The focused ownership command ran against a generated temporary project seeded
from `apps/macos/TSB/Package.resolved`:

```sh
xcodebuild \
  -project "$diagnostic_tmp/project/TSB.xcodeproj" \
  -scheme TSB \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$diagnostic_tmp/TestData" \
  -clonedSourcePackagesDirPath "$diagnostic_tmp/SourcePackages" \
  -resultBundlePath "$diagnostic_tmp/focused.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution \
  -only-testing:TSBTests/SessionCoordinatorTests/testOlderASRCompletionCannotClearTheNewSessionProcessingOwnership \
  -test-iterations "$ITERATIONS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" test
```

At `056d120`, 31 of 4,100 focused repetitions failed only because `copyCount`
was observed before child-task delivery completed; saved state and the newer
session's ownership state passed. In a temporary source copy, the `deaf650`
test false-passed 1/1 against an all-processing-task-removal mutant, while the
strengthened test produced 0 passed and 1 failed, as expected. The tracked real
source was not mutated.

## Current documentation-tree checks

The evidence publication did not rerun the full build command. These bounded
commands passed on the documentation head:

```sh
/bin/sh scripts/test-verify-tsb.sh
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "workflow yaml parsed"'
/bin/sh apps/macos/TSB/scripts/settings-static-gate.sh
git diff --check
git ls-files .superpowers
```

The commands respectively printed `verify-tsb self-check passed`, `workflow
yaml parsed`, and `TSB settings static gate passed`; the diff check exited 0
and the final command returned no paths. A dynamic tracked-content scan
constructed the current developer path and local-machine email from `id -un`
and `hostname -s`; neither it nor the WeChat identifier prefix occurred. The
only email-like matches were reserved `example.test` fixtures. Recognized
secret/private-key patterns were absent. Tracked path and Git-mode scans found
no runtime audio, model weight, database, signing/build artifact, generated
Xcode project, symlink or submodule.

## Evidence boundary

- The hygiene branch is not pushed. No hygiene Draft PR, GitHub CI result,
  branch-protection rule, Ready transition or merge is proven here.
- PR #11 remains separate from this work.
- This evidence proves no signing, notarization, release, user-product
  acceptance, Golden Set, M09 or M10 result.
- The installed `~/Applications/TSB.app` predates this branch and was not
  updated by repository hygiene.

The complete change/deviation/rollback mapping remains in
[`docs/execution/EXE-WP-HYGIENE.md`](../docs/execution/EXE-WP-HYGIENE.md).
