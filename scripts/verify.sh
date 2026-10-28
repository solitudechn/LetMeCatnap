#!/bin/bash

# Everything that has to pass before a commit is worth pushing: formatting,
# localization, unit tests, shell syntax. GitHub Actions runs the same checks
# (see .github/workflows/ci.yml), so a green run here means a green CI.
#
#   ./scripts/verify.sh
#
# Set CATNAP_SWIFT_FLAGS=--disable-sandbox when SwiftPM's manifest sandbox cannot
# run in your environment (it fails with "sandbox_apply: Operation not permitted"
# inside nested sandboxes).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# SwiftUI macros need a full Xcode, same detection as build.sh.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    xcodeApp="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1 || true)"
    if [ -n "$xcodeApp" ]; then
        DEVELOPER_DIR="$xcodeApp/Contents/Developer"
        export DEVELOPER_DIR
    fi
fi

swiftExtra="${CATNAP_SWIFT_FLAGS:-}"

echo "==> swift format lint"
swift format lint --recursive --strict src core Tests

echo "==> localization"
python3 scripts/check-l10n.py

echo "==> unit tests"
swift test --filter CatnapCoreTests $swiftExtra

echo "==> shell syntax"
bash -n build.sh

echo ""
echo "all checks passed"
