# EXE-WP-HYGIENE: Repository hygiene

- Plan: [`docs/superpowers/plans/2026-09-06-tsb-repository-hygiene.md`](../superpowers/plans/2026-09-06-tsb-repository-hygiene.md)
- Evidence: [`evidence/WP-HYGIENE-LOCAL-GATE.md`](../../evidence/WP-HYGIENE-LOCAL-GATE.md)
- Engineering standard: sections 2, 3, 5, 6, 7 and 8 of [`docs/standards/engineering-standard.md`](../standards/engineering-standard.md)
- Decision: no new ADR; this work applies the existing repository standard
- Owner: Sol controller with task-scoped implementation owners
- Independent reviewers: separate read-only spec/code reviewers for Tasks 1-8 and whole-branch Git/privacy reviewers
- Status: passed locally through the pre-record head; record review and remote integration remain pending
- Branch: `codex/tsb-repo-hygiene`
- Repository comparison base: `9f95c40`
- Current pre-record head: `6e3cb80`
- Implementation range: `9f95c40..6e3cb80`
- Initial execution-record commit: `0fa783c`
- Evidence-publication plan correction: `532a792`
- Latest evidence/link commit: resolve with `git log -1 --format='%H %s' -- evidence/WP-HYGIENE-LOCAL-GATE.md docs/execution/EXE-WP-HYGIENE.md`
- Started: 2026-09-06
- Finished: 2026-09-06 (local implementation only)

## Traceability

| WP / requirement | Files | Tests and evidence | Commits |
|---|---|---|---|
| WP-HYGIENE / one verification entrypoint and hermetic orchestration self-test | `scripts/verify-tsb.sh`; `scripts/test-verify-tsb.sh` | [Local-gate evidence](../../evidence/WP-HYGIENE-LOCAL-GATE.md): self-test passed; full gates exercised the same entrypoint | `79cccc7`, `c277332`, `d59c131` |
| WP-HYGIENE / authenticate SenseVoice before extraction | `scripts/bootstrap-sensevoice-model.sh` | Tampered-archive RED; SenseVoice self-check GREEN | `35d1597` |
| WP-HYGIENE / MIT, repository chain and version `0.2.0 (1)` | `LICENSE`; `.gitignore`; root `README.md`; `apps/macos/TSB/project.yml`; engineering standard | Generated build settings and documentation diff passed review | `bae426f` |
| WP-HYGIENE / pinned CI calling the one local gate | `.github/workflows/ci.yml` | Workflow YAML parse and orchestration self-check passed locally | `6233ac7` |
| WP-HYGIENE / stop tracking Agent scratch and remove the workstation path | ten `.superpowers/sdd/` index removals; one formal plan path | Local files preserved; current-tree privacy checks below passed | `c9c166b` |
| WP-HYGIENE / isolate the XCTest host from standard defaults and login Keychain | app scheme/composition root, settings model, focused settings test and static gate | RED compile check; focused 1/1; static gate; two consecutive full gates | `26005b1`, `593a058` |
| WP-HYGIENE / lock the generated app package graph | `apps/macos/TSB/Package.resolved`; both verification scripts | Orchestration RED/GREEN and one locked full gate | `056d120` |
| WP-HYGIENE / deterministic processing-ownership regression | `SessionCoordinatorTests.swift` only | 31/4,100 historical RED; mutant proof; real-source 100/100; full gate | `deaf650`, `21dcb32` |
| WP-HYGIENE / plan, reviewed corrections, record and indexed evidence | hygiene plan; this file; execution/evidence indexes; local-gate evidence | Commit resolution, indexed links, diff and privacy checks | `e1c9df7`, `8ad6bf8`, `fef9eb6`, `31bf58b`, `095801c`, `9e04513`, `7e82fd8`, `6e3cb80`, `0fa783c`, `532a792`; latest evidence/link commit resolved by the command above |

## Commit map

Every implementation commit in `9f95c40..6e3cb80` is accounted for. Plan and
review corrections are grouped; build, security and test changes remain
explicit. Documentation follow-ups are listed after the implementation range.

| Commits | Actual change |
|---|---|
| `e1c9df7` | Added the repository-hygiene plan. |
| `79cccc7`, `c277332`, `d59c131` | Added the one-command gate and self-test, then fixed isolated XcodeGen setup and signal-status preservation found in review. |
| `8ad6bf8` | Corrected the CI plan for cold-run constraints. |
| `35d1597` | Added pinned SenseVoice archive SHA-256 verification before extraction. |
| `bae426f` | Added MIT, the repository/worktree contract and app version identity. |
| `6233ac7` | Added the pinned macOS CI workflow that calls the shared gate. |
| `fef9eb6`, `31bf58b` | Added scratch-cleanup scope and made the privacy check self-excluding. |
| `c9c166b` | Stopped tracking ten local Agent scratch files and made one formal worktree path repository-relative. |
| `095801c` | Recorded the XCTest-host isolation deviation and fix plan. |
| `26005b1`, `593a058` | Isolated test-host startup from real standard defaults/login Keychain and anchored both halves in the static gate after review. |
| `9e04513` | Recorded the final reproducibility gaps. |
| `056d120` | Added and enforced the app-specific SwiftPM lock for both test and independent build. |
| `7e82fd8` | Recorded the deterministic ownership-regression plan. |
| `deaf650`, `21dcb32` | Replaced a scheduler guess with delivery completion, then directly asserted processing ownership after mutant review. |
| `6e3cb80` | Corrected the plan to describe the direct ownership assertion. |
| `0fa783c` | Added the initial execution record and its execution index link. |
| `532a792` | Corrected Task 9 to require a bounded, tracked and indexed local-gate evidence page. |
| Latest evidence/link commit | Resolve through the file-history command in the metadata; it adds the evidence page/index link without self-referential hash churn. |

## Commands and results

The supported full command is:

```sh
/bin/sh scripts/verify-tsb.sh
```

Accepted full-gate results were Python **5/5**, SenseVoice **7/7**, Paraformer
**11/11**, macOS app XCTest **395/395**, and a successful independent unsigned
Debug app build.

- At `593a058`, two consecutive full commands passed on the same head after
  XCTest-host Keychain isolation. Both crossed the former pre-attach wait and
  removed their validated temporary directories.
- At `056d120`, one full command passed with the tracked app lock and immutable
  package resolution. A later full command at the same head exposed the
  scheduler-dependent ownership test: 31 of 4,100 focused repetitions failed,
  only because `copyCount` was asserted before delivery completed; the recorded
  session and newer-session ownership state passed.
- A temporary mutant proved that the `deaf650` test false-passed when all
  processing tasks were wrongly removed, while the strengthened test failed.
  The real source then passed the focused test 100/100 and the full 395/395 gate
  at `21dcb32`; production code was never changed by the test fix.

The focused ownership repetitions used the generated temporary project, tracked
lock and immutable-resolution flags:

```sh
xcodebuild \
  -project "$diagnostic_tmp/project/TSB.xcodeproj" \
  -scheme TSB -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$diagnostic_tmp/TestData" \
  -clonedSourcePackagesDirPath "$diagnostic_tmp/SourcePackages" \
  -resultBundlePath "$diagnostic_tmp/focused.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  -disableAutomaticPackageResolution \
  -only-testing:TSBTests/SessionCoordinatorTests/testOlderASRCompletionCannotClearTheNewSessionProcessingOwnership \
  -test-iterations "$ITERATIONS" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" test
```

The current documentation-only head reran no full build gate. These bounded
checks passed: `/bin/sh scripts/test-verify-tsb.sh`, workflow parsing with Ruby
`YAML.load_file`, `/bin/sh apps/macos/TSB/scripts/settings-static-gate.sh`,
`git diff --check`, commit resolution and the current-tree privacy checks.

## Deviations found and closed

- Worktree/scratch sprawl: local Agent reports were untracked without deleting
  their physical copies or rewriting history. The separate local archive is
  retained at `~/Library/Application Support/TSB/Archives.noindex/repository/2026-09-06-pre-hygiene/`.
- Unauthenticated SenseVoice archive: the fixed release asset is now checked
  against its pinned SHA-256 before extraction.
- Missing one-command/CI gate: one local entrypoint now owns the sequence and the
  pinned workflow calls it.
- XCTest host read real standard defaults and the login Keychain: test-action
  startup now skips only persisted-settings loading; production Run/Release
  behavior is unchanged.
- Missing app SwiftPM lock: the app-specific lock is tracked, seeded into the
  generated workspace, and automatic resolution is disabled for test/build.
- Scheduler-dependent ownership test: delivery completion replaced the single
  yield, and ownership is now asserted directly with mutant evidence.

## Current-tree privacy result

`git ls-files .superpowers` is empty. A dynamic scan constructed the current
developer path and local-machine email from `id -un` and `hostname -s`; neither
it nor the WeChat identifier prefix occurred in tracked text. The only
email-like matches were reserved `example.test` fixtures, not real addresses.
Recognized secret/private key patterns were absent. Tracked-path and Git-mode
scans found no runtime audio, model weight, database, signing/build artifact,
generated Xcode project, symlink, or submodule.

## Open boundaries

- `codex/tsb-repo-hygiene` is not pushed; there is no hygiene Draft PR or GitHub
  CI run, and `main` protection is not configured. The branch is not merged.
- PR #11 remains a separate open Draft from `codex/v02-local-daily` to `main`.
- No signing, notarization, release, user-product acceptance, Golden Set, M09 or
  M10 is proven by this repository-hygiene work.
- The installed `~/Applications/TSB.app` predates this branch and was not
  updated; its executable modification date is 2026-08-26.
- Several early hygiene commit subjects lack the literal scope required by the
  now-documented commit standard. Their reviewed SHAs are preserved; later
  commits use scopes.

## Rollback

Revert the atomic commits in reverse order or revert the branch range. Local
archives remain separate and must not be removed by repository rollback. Do not
rewrite history or run Git garbage collection as part of rollback.
