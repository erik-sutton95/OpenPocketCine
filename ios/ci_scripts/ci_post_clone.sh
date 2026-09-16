#!/bin/sh
# Xcode Cloud: generate the Xcode project and inject Frame.io PKCE values
# plus an optional Sentry DSN. The xcodeproj is gitignored and produced by
# XcodeGen; this script must run before xcodebuild. Frameio.local.xcconfig
# and Reliability.local.xcconfig are gitignored. Empty-safe: missing vars
# reproduce the default (Frame.io login disabled, Sentry DSN empty, non-fatal)
# unless SENTRY_UPLOAD_ENABLED=true, which requires a DSN at clone time.
# Successful archives always verify the packaged DSN in ci_post_xcodebuild.sh.
#
# Xcode Cloud passes -disableAutomaticPackageResolution, so the generated
# workspace must contain Package.resolved. xcodegen postGenCommand copies
# ios/Package.resolved; the explicit sync below is the same copy if that
# hook is missing.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi
(cd ios && xcodegen generate)
sh ios/sync-package-resolved.sh

cat > ios/OpenPocketCine/Frameio.local.xcconfig <<EOF
FRAMEIO_CLIENT_ID = ${FRAMEIO_CLIENT_ID:-}
FRAMEIO_REDIRECT_URI = ${FRAMEIO_REDIRECT_URI:-}
FRAMEIO_URL_SCHEME = ${FRAMEIO_URL_SCHEME:-}
EOF

if [ -z "${FRAMEIO_CLIENT_ID:-}" ]; then
  echo "warning: FRAMEIO_CLIENT_ID not set — Frame.io login will be disabled in this build."
fi

# Sentry public DSN for the Cocoa SDK. xcconfig encoding lives in
# tools/sentry-dsn-xcconfig.py so https:// is not treated as a comment.
# Prefer SENTRY_DSN_IOS; SENTRY_DSN is the fallback. Never echo the value.
if [ "${SENTRY_UPLOAD_ENABLED:-}" = "true" ]; then
  python3 ./tools/sentry-dsn-xcconfig.py --out ios/OpenPocketCine/Reliability.local.xcconfig --require
else
  python3 ./tools/sentry-dsn-xcconfig.py --out ios/OpenPocketCine/Reliability.local.xcconfig
fi
