#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -parse-as-library -swift-version 5 \
    Sources/MihonMac/Models.swift \
    Sources/MihonMac/LibraryStore.swift \
    Sources/MihonMac/ArchiveUtility.swift \
    Sources/MihonMac/SampleLibrary.swift \
    Sources/MihonMac/ContentLoader.swift \
    Sources/MihonMac/NetworkService.swift \
    Tests/SmokeMain.swift Tests/ReaderSmokeChecks.swift Tests/NetworkSmokeChecks.swift \
    -o .build/koma-smoke-tests
.build/koma-smoke-tests
