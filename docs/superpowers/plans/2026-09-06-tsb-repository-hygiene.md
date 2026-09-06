# TSB Repository Hygiene Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the local repository and GitHub path follow one reproducible chain from an isolated `codex/*` worktree through one verification command, Draft PR review, required CI, and finally `main`.

**Architecture:** Keep the existing app module layout unchanged. Add one shell entrypoint that owns all repository verification, have GitHub Actions call that same entrypoint, authenticate downloaded build inputs before use, and document the local/main/worktree boundary without adding new application abstractions.

**Tech Stack:** POSIX `sh`, Xcode 26.6, Swift 6.3.3, XcodeGen 2.46.0, XcodeGen YAML, GitHub Actions, MIT License.

**Spec:** `docs/standards/engineering-standard.md`

## Global Constraints

- Start from `origin/main@9f95c40a63bb9fee3fa409981d24a133a47c01eb` on `codex/tsb-repo-hygiene` in `.worktrees/tsb-repo-hygiene`.
- Do not move or refactor files under `apps/macos/TSB/TSB` or `apps/macos/TSB/TSBTests`.
- The checked-in Xcode source of truth remains `apps/macos/TSB/project.yml`; generated `TSB.xcodeproj` remains ignored.
- The canonical app SwiftPM lock remains tracked at `apps/macos/TSB/Package.resolved`; verification seeds it into the generated project and forbids automatic package resolution.
- The reproducible toolchain is macOS 26.5.2 arm64, Xcode 26.6, Swift 6.3.3, and XcodeGen 2.46.0.
- CI runs on `macos-26`, sets `DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer`, and installs the XcodeGen 2.46.0 release zip only after matching SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`.
- `actions/checkout` is pinned to commit `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7.0.1`) with `persist-credentials: false` and workflow permission `contents: read`.
- CI and developers run the same `scripts/verify-tsb.sh`; there is no second copy of the build/test sequence in workflow YAML.
- Verification runs every deterministic repository gate: shell syntax, settings and model/audio self-checks, Python corpus tests, both Swift probe suites, project generation, the full unsigned app test suite, an independent unsigned Debug build, and `git diff HEAD --check`.
- The generated project, SwiftPM scratch paths, SourcePackages, result bundle, and Debug build all live under one validated temporary directory and are removed on exit; verification must not leave generated files in the checkout.
- When the Fun-ASR installer and local-signing scripts arrive on a later branch, the same entrypoint detects only complete file pairs, runs their self-checks, and signs only the independent build artifact, never the test product containing `TSBTests.xctest`.
- Runtime audio, transcripts, model weights, API keys, signing assets, DerivedData, generated projects, and local review notes remain outside Git.
- Repository-owned code and documentation use MIT; existing third-party attribution and third-party asset licenses remain separate and unchanged.
- Do not add SwiftLint, SwiftFormat, Make, Just, a package manager, a cache action, CODEOWNERS, or new application-layer abstractions.

---

### Task 1: Single local verification command

**Files:**
- Create: `scripts/test-verify-tsb.sh`
- Create: `scripts/verify-tsb.sh`

**Interfaces:**
- Consumes: `apps/macos/TSB/project.yml`, all existing deterministic repository self-checks/tests, and the local command-line toolchain.
- Produces: `scripts/verify-tsb.sh`, the only supported full repository gate, plus a hermetic orchestration self-test that runs the real entrypoint against a miniature fake repository.

- [ ] **Step 1: Write the failing orchestration test**

  Create `scripts/test-verify-tsb.sh` as a POSIX shell test. It creates a temporary miniature repository containing copied `verify-tsb.sh`, empty valid `project.yml`, and executable fake versions of the four repository gate scripts. It prepends fake `git`, `xcodegen`, `xcodebuild`, `xcrun`, `swift`, and `python3` commands to `PATH`; every fake appends its observable operation to `TSB_VERIFY_LOG`. Fake `git -C ... rev-parse --show-toplevel` returns `TSB_FAKE_REPO`; fake XcodeGen prints `Version: ${TSB_FAKE_XCODEGEN_VERSION:-2.46.0}` for `--version`; fake xcodebuild creates `BuildData/Build/Products/Debug/TSB.app` for the build operation.

  The test runs `/bin/sh scripts/verify-tsb.sh` with those fakes and compares the log against these behaviors in this order:

  ```text
  git diff HEAD --check
  settings-static-gate
  bootstrap-sensevoice-model --self-check
  bootstrap-paraformer-model --self-check
  probe-retained-audio --self-check
  python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
  swift test --package-path probes/sensevoice
  swift test --package-path probes/paraformer
  xcodegen generate
  xcodebuild test
  xcrun xcresulttool get test-results summary
  xcodebuild build
  ```

  Normalize long XcodeGen/xcodebuild argument lists to the operation names above. Assert that the build-created app exists and that the entrypoint rejects an injected `TSBTests.xctest`. Run a second case with `TSB_FAKE_XCODEGEN_VERSION=2.45.0`; it must fail before any repository gate executes. Temporary files are removed by a trap.

- [ ] **Step 2: Run the test and observe RED**

  Run:

  ```bash
  /bin/sh scripts/test-verify-tsb.sh
  ```

  Expected: non-zero because `scripts/verify-tsb.sh` does not exist.

- [ ] **Step 3: Implement the minimum verification entrypoint**

  Create executable `scripts/verify-tsb.sh` with `set -eu`. Resolve the repository root with `git -C "$script_dir/.." rev-parse --show-toplevel`; define `app_root`; then require `git`, `xcodegen`, `xcodebuild`, `xcrun`, `swift`, `python3`, `ffmpeg`, `rg`, `mktemp`, `find`, `curl`, `tar`, `shasum`, and `awk`. Require exact XcodeGen output `Version: 2.46.0` before running repository gates.

  Detect the later Fun-ASR/signing additions with these all-or-nothing contracts:

  ```sh
  # Fun-ASR is enabled only when both are present.
  apps/macos/TSB/TSB/Core/Transcription/FunASRTranscriber.swift
  scripts/install-funasr-runtime.sh  # regular executable

  # Local signing is enabled only when both are executable.
  apps/macos/TSB/scripts/sign-local-app.sh
  apps/macos/TSB/scripts/test-local-signing.sh
  ```

  Create `mktemp -d "${TMPDIR:-/tmp}/verify-tsb.XXXXXX"`; validate the basename against `verify-tsb.*`; install EXIT/HUP/INT/TERM traps; and delete only that validated directory with `find "$verify_tmp" -depth -delete`. Set `TMPDIR` to a child of the verified directory. Execute these deterministic gates in order:

  ```sh
  git diff HEAD --check
  sh -n scripts/verify-tsb.sh \
    apps/macos/TSB/scripts/settings-static-gate.sh \
    scripts/bootstrap-sensevoice-model.sh \
    scripts/bootstrap-paraformer-model.sh \
    scripts/probe-retained-audio.sh
  apps/macos/TSB/scripts/settings-static-gate.sh
  scripts/bootstrap-sensevoice-model.sh --self-check
  scripts/bootstrap-paraformer-model.sh --self-check
  scripts/probe-retained-audio.sh --self-check
  python3 -m unittest scripts/tests/test_prepare_g0_corpus.py
  swift test --package-path probes/sensevoice --scratch-path "$verify_tmp/sensevoice-build"
  swift test --package-path probes/paraformer --scratch-path "$verify_tmp/paraformer-build"
  xcodegen generate --quiet \
    --spec "$app_root/project.yml" \
    --project "$verify_tmp/project" \
    --project-root "$app_root" \
    --cache-path "$verify_tmp/xcodegen-cache"
  xcodebuild -quiet \
    -project "$verify_tmp/project/TSB.xcodeproj" \
    -scheme TSB \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$verify_tmp/TestData" \
    -clonedSourcePackagesDirPath "$verify_tmp/SourcePackages" \
    -resultBundlePath "$verify_tmp/TSBTests.xcresult" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" test
  xcrun xcresulttool get test-results summary \
    --compact --path "$verify_tmp/TSBTests.xcresult"
  xcodebuild -quiet \
    -project "$verify_tmp/project/TSB.xcodeproj" \
    -scheme TSB \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$verify_tmp/BuildData" \
    -clonedSourcePackagesDirPath "$verify_tmp/SourcePackages" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "CODE_SIGN_IDENTITY=" build
  ```

  Require `$verify_tmp/BuildData/Build/Products/Debug/TSB.app` and reject a bundled `Contents/PlugIns/TSBTests.xctest`. When the optional feature files are present, syntax-check and self-check the installer, then sign/test only this independent BuildData app. Print final `TSB verification passed` and preserve all underlying exit statuses.

- [ ] **Step 4: Run the self-test and observe GREEN**

  Run:

  ```bash
  /bin/sh scripts/test-verify-tsb.sh
  ```

  Expected: `verify-tsb self-check passed`, exit 0.

- [ ] **Step 5: Run shell syntax checks**

  Run:

  ```bash
  /bin/sh -n scripts/verify-tsb.sh
  /bin/sh -n scripts/test-verify-tsb.sh
  git diff --check
  ```

  Expected: all exit 0.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/verify-tsb.sh scripts/test-verify-tsb.sh
  git commit -m "build: add one-command TSB verification"
  ```

---

### Task 2: Authenticate the SenseVoice archive before extraction

**Files:**
- Modify: `scripts/bootstrap-sensevoice-model.sh`

**Interfaces:**
- Consumes: the existing fixed `MODEL_URL` and the official release asset bytes.
- Produces: pre-extraction archive authentication against SHA-256 `7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e`.

- [ ] **Step 1: Extend the existing self-check with a failing tamper case**

  Before production verification code is added, extend `self_check()` to build a syntactically valid tar.bz2 containing the expected source directory and all three required files. Add a temporary fake `curl` that copies this fixture to its `-o` destination and a fake `shasum` that returns 64 zeroes only when hashing the archive, delegating all other calls to a captured real `shasum` path.

  Invoke the script recursively with the fake tools and an unused target. The self-check must fail if that recursive bootstrap succeeds:

  ```sh
  if SENSEVOICE_TEST_ARCHIVE="$tampered_archive" \
      SENSEVOICE_REAL_SHASUM="$real_shasum" \
      PATH="$fake_bin:$PATH" \
      /bin/sh "$0" --target "$tmp_dir/tampered-target" >/dev/null 2>&1; then
    die "self-check expected tampered archive to fail"
  fi
  ```

  The fake `curl` reads `SENSEVOICE_TEST_ARCHIVE`; the fake `shasum` delegates with `exec "$SENSEVOICE_REAL_SHASUM" "$@"` for every non-archive operation.

- [ ] **Step 2: Run the self-check and observe RED**

  Run:

  ```bash
  /bin/sh scripts/bootstrap-sensevoice-model.sh --self-check
  ```

  Expected: non-zero with `self-check expected tampered archive to fail`, because the current implementation never authenticates the archive.

- [ ] **Step 3: Add the minimum pre-extraction verification**

  Add this constant beside `MODEL_ARCHIVE`:

  ```sh
  MODEL_ARCHIVE_SHA256="7d1efa2138a65b0b488df37f8b89e3d91a60676e416f515b952358d83dfd347e"
  ```

  Add a `verify_sha256 FILE EXPECTED LABEL` helper that computes `shasum -a 256`, compares the first field exactly, and dies with `<label> SHA-256 mismatch` on inequality. In `bootstrap_model()`, call it immediately after `curl` and before `tar`:

  ```sh
  verify_sha256 "$archive" "$MODEL_ARCHIVE_SHA256" "model archive"
  ```

- [ ] **Step 4: Run the self-check and observe GREEN**

  Run:

  ```bash
  /bin/sh scripts/bootstrap-sensevoice-model.sh --self-check
  ```

  Expected: `self-check passed`, exit 0.

- [ ] **Step 5: Run syntax and diff checks**

  ```bash
  /bin/sh -n scripts/bootstrap-sensevoice-model.sh
  git diff --check
  ```

  Expected: both exit 0.

- [ ] **Step 6: Commit**

  ```bash
  git add scripts/bootstrap-sensevoice-model.sh
  git commit -m "fix(model): verify SenseVoice archive digest"
  ```

---

### Task 3: Repository contract, MIT license, and version identity

**Files:**
- Create: `LICENSE`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `apps/macos/TSB/project.yml`
- Modify: `docs/standards/engineering-standard.md`

**Interfaces:**
- Consumes: the existing documentation hierarchy and XcodeGen settings.
- Produces: an explicit MIT grant, a stable local-only folder, version `0.2.0 (1)`, and one documented Git/worktree/PR chain.

- [ ] **Step 1: Add the MIT license**

  Add the canonical MIT text with:

  ```text
  MIT License

  Copyright (c) 2026 The Second Brain contributors
  ```

  Preserve the standard permission, inclusion, warranty-disclaimer, and liability paragraphs verbatim. Do not move or shorten the separate OpenDictation notice in `apps/macos/TSB/UPSTREAM.md`.

- [ ] **Step 2: Establish the local-only folder contract**

  Add `/.local/` to `.gitignore` under a `# Local workspace notes` comment. This directory is for local review reports and manifests only; runtime data remains under Application Support and worktrees remain under `.worktrees/`.

- [ ] **Step 3: Replace stale README status and add one operating path**

  Replace the hard-coded branch and `394` test statement with wording that says `main` is the reviewed baseline, active changes live in Draft PRs, and exact automated counts belong to GitHub Checks and the acceptance matrix. Keep the explicit boundary that no signed/notarized public release is proven.

  Add a `本地生成与验证` section containing the exact current toolchain and only this public command:

  ```bash
  ./scripts/verify-tsb.sh
  ```

  Explain that it generates the ignored Xcode project, runs static/bootstrap checks, the full unsigned tests, and an unsigned Debug build. Add a `Git 主链` section with this exact flow:

  ```text
  origin/main
    -> codex/<scope> isolated worktree
    -> ./scripts/verify-tsb.sh
    -> Draft PR
    -> independent review + GitHub required check
    -> Ready for review
    -> merge to main
    -> remove merged worktree and branch
  ```

  Add a license note linking `LICENSE`, `apps/macos/TSB/UPSTREAM.md`, and `references/README.md`, explicitly stating that model weights and public corpora keep their own licenses and are not relicensed by the repository MIT grant.

- [ ] **Step 4: Add application version identity**

  Under the app target base settings in `apps/macos/TSB/project.yml`, add:

  ```yaml
  MARKETING_VERSION: 0.2.0
  CURRENT_PROJECT_VERSION: 1
  ```

- [ ] **Step 5: Align the engineering standard with the local chain**

  In `docs/standards/engineering-standard.md` section 3, add requirements that the root checkout tracks `origin/main`, each active `codex/<scope>` branch has one isolated worktree, Draft precedes Ready, required checks and independent review precede merge, and merged worktrees/branch pointers are removed only after their commits are reachable from `main`. State that removal of a merged branch does not remove Git history.

- [ ] **Step 6: Verify generated version settings and documentation diff**

  Run:

  ```bash
  xcodegen generate --spec apps/macos/TSB/project.yml
  xcodebuild -project apps/macos/TSB/TSB.xcodeproj -scheme TSB -showBuildSettings \
    | grep -E 'MARKETING_VERSION = 0.2.0|CURRENT_PROJECT_VERSION = 1'
  git diff --check
  ```

  Expected: both version settings appear and `git diff --check` exits 0.

- [ ] **Step 7: Commit**

  ```bash
  git add LICENSE .gitignore README.md apps/macos/TSB/project.yml docs/standards/engineering-standard.md
  git commit -m "docs: define the TSB repository contract"
  ```

---

### Task 4: GitHub required-check workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `scripts/test-verify-tsb.sh` and `scripts/verify-tsb.sh` from Task 1.
- Produces: one `CI / macos-xcode-26.6` status check for every pull request and every push to `main`.

- [ ] **Step 1: Add the minimum workflow configuration**

  Create `.github/workflows/ci.yml` with:

  ```yaml
  name: CI

  on:
    pull_request:
    push:
      branches: [main]

  permissions:
    contents: read

  jobs:
    macos:
      name: macos-xcode-26.6
      runs-on: macos-26
      timeout-minutes: 60
      env:
        DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
        HOMEBREW_NO_AUTO_UPDATE: "1"
        XCODEGEN_VERSION: "2.46.0"
        XCODEGEN_SHA256: 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
      steps:
        - name: Checkout
          uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
          with:
            persist-credentials: false
        - name: Verify Xcode
          run: |
            test -d "$DEVELOPER_DIR"
            xcodebuild -version | grep -F "Xcode 26.6"
            swift --version
        - name: Install deterministic-test prerequisites
          shell: bash
          run: |
            set -euo pipefail
            missing=()
            command -v ffmpeg >/dev/null 2>&1 || missing+=(ffmpeg)
            command -v rg >/dev/null 2>&1 || missing+=(ripgrep)
            if (( ${#missing[@]} )); then
              brew install "${missing[@]}"
            fi
            for tool in python3 ffmpeg rg curl tar shasum awk; do
              command -v "$tool"
            done
        - name: Install XcodeGen
          run: |
            set -euo pipefail
            archive="$RUNNER_TEMP/xcodegen-${XCODEGEN_VERSION}.zip"
            install_dir="$RUNNER_TEMP/xcodegen-${XCODEGEN_VERSION}"
            curl -fsSL \
              "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip" \
              -o "$archive"
            echo "${XCODEGEN_SHA256}  ${archive}" | shasum -a 256 -c -
            mkdir -p "$install_dir"
            ditto -x -k "$archive" "$install_dir"
            echo "$install_dir/xcodegen/bin" >> "$GITHUB_PATH"
            "$install_dir/xcodegen/bin/xcodegen" --version \
              | grep -Fx "Version: ${XCODEGEN_VERSION}"
        - name: Verify orchestration contract
          run: /bin/sh scripts/test-verify-tsb.sh
        - name: Verify TSB
          run: /bin/sh scripts/verify-tsb.sh
  ```

  Do not add dependency caching in the first version. `ffmpeg` and `rg` are not part of the documented `macos-26` runner contract, so install only whichever command is absent; disable Homebrew auto-update to avoid an unrelated update step. Use 60 minutes until two or three cold-run observations justify a lower limit.

- [ ] **Step 2: Parse the YAML and run local workflow-equivalent checks**

  Run:

  ```bash
  ruby -e 'require "yaml"; YAML.load_file(".github/workflows/ci.yml"); puts "workflow yaml parsed"'
  /bin/sh scripts/test-verify-tsb.sh
  /bin/sh scripts/verify-tsb.sh
  ```

  Expected: YAML parse exits 0, the self-check passes, and the complete verification exits 0.

- [ ] **Step 3: Inspect the complete branch diff**

  Run:

  ```bash
  git status --short
  git diff --check
  git diff --stat origin/main...HEAD
  git log --oneline origin/main..HEAD
  ```

  Expected: only this plan's intended repository-hygiene files differ from `origin/main`.

- [ ] **Step 4: Commit**

  ```bash
  git add .github/workflows/ci.yml
  git commit -m "ci: verify TSB on the pinned macOS toolchain"
  ```

---

### Task 5: Stop tracking local agent scratch

**Files:**
- Stop tracking: the 10 existing files under `.superpowers/sdd/`
- Modify: `docs/superpowers/plans/2026-08-25-tsb-v0.2-transcript-polish-implementation.md`

**Interfaces:**
- Consumes: the existing `.superpowers/` ignore rule and historical process files.
- Produces: a current Git tree without local Agent scratch or workstation-absolute paths; local files and Git history remain intact.

- [ ] **Step 1: Preserve local data while removing it from the current index**

  Confirm the tracked set with `git ls-files .superpowers`. Use `git rm --cached` on exactly those 10 paths so the ignored local files remain on disk. Do not delete their content and do not rewrite history.

- [ ] **Step 2: Make the one formal absolute path portable**

  In the 2026-08-25 transcript-polish implementation plan, replace its sole developer-absolute worktree path with `.worktrees/wp-04-alpha2`.

- [ ] **Step 3: Verify the current tree contract**

  Run:

  ```bash
  test -z "$(git ls-files .superpowers)"
  developer_path="/Users""/$(id -un)"
  developer_mail="$(id -un)@$(hostname -s)"".local"
  wechat_prefix="wxid""_"
  test -z "$(git grep -Il -F -e "$developer_path" -e "$developer_mail" -e "$wechat_prefix" -- .)"
  /bin/sh scripts/test-verify-tsb.sh
  git diff --check
  git diff --cached --check
  ```

  Confirm all 10 local scratch files still exist on disk.

- [ ] **Step 4: Commit**

  Commit only the staged removals and the one formal plan edit:

  ```bash
  git commit -m "chore(repo): untrack local agent scratch"
  ```

---

### Task 6: Isolate the XCTest host from user settings and Keychain

**Files:**
- Modify: `apps/macos/TSB/project.yml`
- Modify: `apps/macos/TSB/TSB/App/TSBAppDelegate.swift`
- Modify: `apps/macos/TSB/TSB/Views/SettingsView.swift`
- Modify: `apps/macos/TSB/TSBTests/System/SettingsSourceTests.swift`
- Modify: `apps/macos/TSB/scripts/settings-static-gate.sh`

**Interfaces:**
- Consumes: the existing hosted XCTest scheme and `SettingsModel` dependency injection.
- Produces: an explicit `TSB_XCTEST_HOST=1` Test-action boundary that prevents application startup from reading the user's standard defaults or login Keychain before XCTest attaches; normal Run and Release startup remain unchanged.

- [ ] **Step 1: Write the failing test-host isolation check**

  Add a focused Settings test that saves a remote endpoint and secret into its existing isolated fixture, creates the launch settings model with `loadPersistedState: false`, and asserts the model retains an empty draft, has no persisted-key flag, and has no error. Run that test before the implementation and observe a compile failure because the parameter does not exist.

- [ ] **Step 2: Add the explicit Test-action marker**

  In the `TSB` scheme's `test` action, set `TSB_XCTEST_HOST: "1"`. Do not use `CFFIXED_USER_HOME`, `XCTestConfigurationFilePath`, XCTest class probing, a test plan, or a second keychain.

- [ ] **Step 3: Skip only launch-time persisted-state loading for the test host**

  Add a defaulted `loadPersistedState: Bool = true` parameter to `SettingsModel.init` and guard only its initial `reloadPersistedState()` call. Thread the same defaulted parameter through `TSBAppDelegate.makeSettingsModel`. In the convenience initializer, pass `false` only when `ProcessInfo.processInfo.environment["TSB_XCTEST_HOST"] == "1"`. Production startup therefore keeps its existing default behavior, while all explicit settings operations and injected-store tests remain unchanged.

- [ ] **Step 4: Guard the configuration before launching XCTest**

  Extend `settings-static-gate.sh` to require the scheme marker and the AppDelegate launch branch. This gate must fail before `xcodebuild test` if either half of the isolation contract is removed.

- [ ] **Step 5: Verify the isolated host twice**

  Run:

  ```bash
  /bin/sh apps/macos/TSB/scripts/settings-static-gate.sh
  /bin/sh scripts/test-verify-tsb.sh
  /bin/sh scripts/verify-tsb.sh
  /bin/sh scripts/verify-tsb.sh
  git diff --check
  ```

  Expected: the static and orchestration checks pass; each full run completes with all app tests and the independent Debug build, without reading the user's login Keychain or leaving generated files in the checkout.

- [ ] **Step 6: Commit**

  ```bash
  git add apps/macos/TSB/project.yml \
    apps/macos/TSB/TSB/App/TSBAppDelegate.swift \
    apps/macos/TSB/TSB/Views/SettingsView.swift \
    apps/macos/TSB/TSBTests/System/SettingsSourceTests.swift \
    apps/macos/TSB/scripts/settings-static-gate.sh
  git commit -m "test(app): isolate the XCTest host from user state"
  ```

---

### Task 7: Lock the generated app's SwiftPM graph

**Files:**
- Create: `apps/macos/TSB/Package.resolved`
- Modify: `scripts/verify-tsb.sh`
- Modify: `scripts/test-verify-tsb.sh`

**Interfaces:**
- Consumes: `project.yml` and the current resolved `sherpa-onnx` 1.13.6 dependency graph.
- Produces: one tracked app-specific SwiftPM lock that is copied into the generated project's workspace before Xcode runs; both test and build reject dependency versions outside that lock.

- [ ] **Step 1: Write the failing orchestration check**

  Extend the miniature repository with a fake canonical `apps/macos/TSB/Package.resolved`. Make fake `xcodebuild` fail unless the lock has been copied to `TSB.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` and both `-onlyUsePackageVersionsFromResolvedFile` and `-disableAutomaticPackageResolution` are present. Run the self-check before production changes and observe RED.

- [ ] **Step 2: Create the canonical app lock**

  Generate a temporary Xcode project from the current `project.yml`, resolve its package graph, and copy only the resulting app-specific `Package.resolved` into `apps/macos/TSB/Package.resolved`. It must pin:

  - `sherpa-onnx` 1.13.6 at revision `1cb484af5e69d3c7803c1eb0b3b5ab8041e0e911`.
  - `onnxruntime-libs` 1.27.1 at revision `1fbef5f2a1b5c2691fe9411243f3a8afe9a0b169`.

- [ ] **Step 3: Seed and enforce the lock in the one verification path**

  After XcodeGen creates the temporary project, create its SwiftPM workspace directory and copy the canonical lock into it. Pass `-onlyUsePackageVersionsFromResolvedFile` and `-disableAutomaticPackageResolution` to both Xcode test and build invocations. Do not add a package manager, cache action, or second build script.

- [ ] **Step 4: Verify RED to GREEN and the real locked build**

  Run:

  ```bash
  /bin/sh scripts/test-verify-tsb.sh
  /bin/sh scripts/verify-tsb.sh
  git diff --check
  ```

  Expected: orchestration self-check passes; the real test/build graph resolves only from the tracked lock; app XCTest remains 395/395 and the independent Debug build succeeds.

- [ ] **Step 5: Commit**

  ```bash
  git add apps/macos/TSB/Package.resolved scripts/verify-tsb.sh scripts/test-verify-tsb.sh
  git commit -m "build(deps): lock the generated app package graph"
  ```

---

### Task 8: Make the session-ownership regression deterministic

**Files:**
- Modify: `apps/macos/TSB/TSBTests/Core/Session/SessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: the existing suspended-transcription harness and `waitForDelivery()` observation.
- Produces: the same ownership regression assertion without depending on a single cooperative scheduler yield.

- [ ] **Step 1: Preserve the observed RED evidence**

  At `056d120`, the focused test failed 31 times across 4,100 repetitions. Every failure was only `copyCount` actual 0 versus expected 1; ASR events, saved record count, and the new main session's `.transcribing` status remained correct. This establishes a scheduling-dependent RED without mutating production code.

- [ ] **Step 2: Replace the scheduler guess with the existing condition**

  In `testOlderASRCompletionCannotClearTheNewSessionProcessingOwnership`, replace the single `await Task.yield()` after completing the older transcription with `await harness.waitForDelivery()`. Keep the subsequent repeated new-session audio callback and all ownership assertions unchanged. Do not edit production code or add a new helper.

- [ ] **Step 3: Verify repeatability and the full gate**

  Run the focused test for 100 iterations from a generated temporary project using the tracked package lock and immutable-resolution flags, then run:

  ```bash
  /bin/sh scripts/verify-tsb.sh
  git diff --check
  ```

  Expected: 100/100 focused repetitions pass; the full gate reports app XCTest 395/395 and the independent Debug build succeeds.

- [ ] **Step 4: Commit**

  ```bash
  git add apps/macos/TSB/TSBTests/Core/Session/SessionCoordinatorTests.swift
  git commit -m "test(session): wait for delivery before ownership assertion"
  ```

---

### Task 9: Publish the execution record

**Files:**
- Create: `docs/execution/EXE-WP-HYGIENE.md`
- Modify: `docs/execution/README.md`

**Interfaces:**
- Consumes: the final reviewed commit range and local validation results.
- Produces: the tracked `WP -> requirements -> files -> tests -> evidence -> commits` record required by the engineering standard, with remote CI and merge status explicitly pending.

- [ ] **Step 1: Record actual work and deviations**

  Add one concise execution record containing owner/reviewer, branch/base/head, intended files, commit mapping, exact test commands and counts, local archive path, privacy scan result, test-host isolation deviation, dependency-lock deviation, rollback, and open risks. State explicitly that GitHub CI, branch protection, Ready, merge, signing/notarization, release, and product acceptance are not yet proven.

- [ ] **Step 2: Index the record**

  Link the new record from `docs/execution/README.md`. Keep detailed raw Agent reports ignored; do not track `.superpowers` again and do not duplicate the full plan.

- [ ] **Step 3: Validate the record against Git**

  Run `git diff --check`, verify every named commit resolves, verify the tree contains no tracked `.superpowers` path or developer-specific absolute path, and leave the worktree clean after commit.

- [ ] **Step 4: Commit**

  ```bash
  git add docs/execution/EXE-WP-HYGIENE.md docs/execution/README.md
  git commit -m "docs(repo): record repository hygiene execution"
  ```

---

## Post-implementation GitHub and local operations

These are integration operations, not implementation tasks:

1. Keep PR #11 Draft and point its review contract at `main@9f95c40` → `codex/v02-local-daily@6ca8523`.
2. Push `codex/tsb-repo-hygiene` and open a separate Draft PR against `main`; do not merge automatically.
3. After the hygiene PR workflow succeeds and the user chooses to merge it, require `CI / macos-xcode-26.6` and pull-request review on `main`.
4. Keep only active worktrees. Before removing merged historical worktrees, copy unique ignored evidence to `~/Library/Application Support/TSB/Archives.noindex/`, verify the copies, and remove only reproducible caches/artifacts.
5. Keep `codex/v02-local-daily` and its worktree until PR #11 is reviewed and explicitly integrated or abandoned.
