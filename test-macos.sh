#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/tests
xcrun swiftc -swift-version 5 -warnings-as-errors \
  macos/Sources/Settings.swift macos/Sources/Engine.swift macos/Sources/Digits.swift \
  macos/Tests/CoreTests.swift -o .build/tests/core-tests
.build/tests/core-tests
if [ "${1:-}" = "--app" ]; then
  xcrun swiftc -swift-version 5 -warnings-as-errors -D APP_TESTS \
    macos/Sources/*.swift macos/Tests/AppTests.swift -o .build/tests/app-tests
  .build/tests/app-tests
fi
