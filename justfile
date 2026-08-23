# OpenPocketCine task runner.
# `just` is the single entry point for repository tasks.
# Run `just` with no arguments to list available recipes.

default:
    @just --list

# ── Setup ──────────────────────────────────────────────────────────────────
# Install the meta-check tools used by `just check` (macOS / Homebrew),
# and enable the repo's git hooks (pre-commit secret scan + proprietary guard).
# Node is required for the public handbook (`just handbook`).
setup:
    brew install node typos-cli editorconfig-checker lychee markdownlint-cli2 actionlint gitleaks swift-format xcodegen
    git config core.hooksPath .githooks

# ── Meta checks (run today; mirrored in CI) ─────────────────────────────────
# Run every repository quality check that this tree currently supports.
# `swift-lint` is available as `just lint` after `just format`; the existing tree is not
# yet fully swift-format clean, so it is not a merge gate.
check: hygiene site-check testflight-notes typos lint-md check-links check-editorconfig lint-actions secrets swift-test

# Reject tracked proprietary, secret-bearing, generated, or machine-specific files.
hygiene:
    ./scripts/check-repository-hygiene.sh

# Validate the deploy-ready landing-page tree and all local asset references.
site-check:
    ./scripts/check-site.sh

# Spell-check the repository.
typos:
    typos

# Lint all Markdown (exclusions in .markdownlint-cli2.jsonc).
lint-md:
    markdownlint-cli2 "**/*.md"

# Check that on-disk links resolve (offline; no network flakiness).
# The GitHub Pages landing page is validated by `site-check` instead.
# handbook/node_modules and build output are generated; skip them.
check-links:
    lychee --no-progress --offline --exclude-path vendor --exclude-path ref --exclude-path docs/design --exclude-path site .

# Verify files obey .editorconfig.
check-editorconfig:
    editorconfig-checker

# Lint GitHub Actions workflows.
lint-actions:
    #!/usr/bin/env bash
    if [ -d .github/workflows ]; then actionlint; else echo "No workflows yet — skipping actionlint."; fi

# Scan committed history for secrets (gitleaks; allowlist in .gitleaks.toml).
secrets:
    #!/usr/bin/env bash
    if command -v gitleaks >/dev/null 2>&1; then
        gitleaks detect --redact --no-banner --config .gitleaks.toml
    else
        echo "gitleaks not installed — run 'just setup'." >&2
        exit 1
    fi

# ── Native production stack ─────────────────────────────────────────────────
# Format shared Swift and iOS app sources.
swift-format:
    swift-format format --in-place --recursive Package.swift Sources Tests ios/OpenPocketCine ios/OpenPocketCineTests

# Lint shared Swift and iOS app sources.
swift-lint:
    swift-format lint --strict --recursive Package.swift Sources Tests ios/OpenPocketCine ios/OpenPocketCineTests

# Run shared Swift core tests.
swift-test:
    swift test

# Run all Swift-only checks.
swift-check: swift-lint swift-test

# Validate TestFlight "What to Test" copy and print it.
testflight-notes:
    ./scripts/ios-release-notes-check.sh
    ./scripts/ios-release-notes-test.sh
    ./scripts/ios-release-notes.sh

# Print the committed iOS marketing version and local build number.
ios-version:
    @sed -n 's/^MARKETING_VERSION = /Version: /p; s/^CURRENT_PROJECT_VERSION = /Build: /p' ios/Config/Version.xcconfig

# Generate the Xcode project from ios/project.yml.
ios-generate:
    cd ios && xcodegen generate

# Build the native iOS app for the simulator.
ios-build: ios-generate
    xcodebuild -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCine -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Run the iOS shell's XCTest suite on the first available iPhone simulator.
ios-test: ios-generate
    #!/usr/bin/env bash
    set -euo pipefail
    device_id="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && !found { print $2; found = 1 }')"
    if [ -z "$device_id" ]; then
        echo "No available iPhone simulator found." >&2
        exit 1
    fi
    xcodebuild -project ios/OpenPocketCine.xcodeproj -scheme OpenPocketCine \
      -destination "platform=iOS Simulator,id=$device_id" \
      test

# Run all native production checks that do not require camera hardware.
# swift-lint is in `just check` / `just lint`; run `just format` before making it a merge gate.
native-check: swift-test ios-test ios-build

# Format production Swift sources.
format: swift-format

# Lint production Swift sources.
lint: swift-lint

# Run production Swift tests.
test: swift-test

# Explain how to run the native production app without invoking prototype tooling.
run:
    #!/usr/bin/env bash
    echo "Generate and open the iOS app:"
    echo "  cd ios && xcodegen generate && open OpenPocketCine.xcodeproj"
    echo "Then run the OpenPocketCine scheme on a physical iPhone (Simulator has no BLE/SoftAP)."
    echo "For command-line verification, use: just ios-build or just native-check."

# Remove SwiftPM build artifacts.
clean:
    swift package clean

# ── Public handbook (Astro Starlight: protocol, apps, setup) ───────────────
# Local preview at http://localhost:4321/. Production is /docs/ on Pages.

handbook:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d handbook/node_modules ]]; then
        npm --prefix handbook ci
    fi
    ASTRO_TELEMETRY_DISABLED=1 npm --prefix handbook run dev -- --host 127.0.0.1 --port 4321

handbook-build:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d handbook/node_modules ]]; then
        npm --prefix handbook ci
    fi
    ASTRO_TELEMETRY_DISABLED=1 HANDBOOK_BASE="${HANDBOOK_BASE:-}" npm --prefix handbook run build

# Merge landing page + handbook into public-site/ as GitHub Pages will ship it.
handbook-stage:
    ./scripts/stage-pages.sh public-site

# ── Android production stack ────────────────────────────────────────────────
# JAVA_HOME falls back to the Homebrew OpenJDK so recipes work without shell setup.

# Cross-compile the shared Swift core + JNI facade for arm64-v8a.
# Requires Swift 6.3.3 + swift-6.3.3-RELEASE_android.
android-core:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew :app:stageSwiftCore

# Build the Android app (debug APK). This also stages the Swift Android core.
android-build:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew assembleDebug

# Run Android JVM unit tests.
android-test:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew test

# Run Android build + unit tests + lint.
android-check:
    cd Apps/Android && JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk}" ./gradlew assembleDebug test lint

# Build and install the debug APK on a connected device/emulator, then launch it.
# With several devices attached, pass the serial: `just android-install R58R92BL76K`.
android-install serial="":
    just android-build
    "${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}/platform-tools/adb" {{ if serial == "" { "" } else { "-s " + serial } }} install -r Apps/Android/app/build/outputs/apk/debug/app-debug.apk
    "${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}/platform-tools/adb" {{ if serial == "" { "" } else { "-s " + serial } }} shell am start -n com.opencapture.openpocketcine/.MainActivity
