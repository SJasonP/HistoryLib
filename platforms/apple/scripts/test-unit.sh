#!/bin/bash
# Build and run hosted unit tests without opening personal history or UI flows.
set -euo pipefail
project_directory="$(cd "$(dirname "$0")/.." && pwd)"
test_destination="${1:-platform=iOS Simulator,name=iPhone Duo}"
test_derived_data="${HISTORYLIB_TEST_DERIVED_DATA:-$(mktemp -d "${TMPDIR:-/tmp}/historylib-unit-tests.XXXXXX")}"
xcodebuild -project "$project_directory/HistoryLib.xcodeproj" -scheme HistoryLib \
  -destination "$test_destination" -derivedDataPath "$test_derived_data" \
  build-for-testing CODE_SIGNING_ALLOWED=NO
python3 - "$test_derived_data/Build/Products" <<'PY'
from pathlib import Path
import plistlib
import sys
products = Path(sys.argv[1])
candidates = [p for p in products.glob('HistoryLib_*.xctestrun') if p.name != 'HistoryLib_UnitOnly.xctestrun']
if not candidates:
    raise SystemExit('No generated HistoryLib test configuration found.')
source = max(candidates, key=lambda p: p.stat().st_mtime_ns)
config = plistlib.loads(source.read_bytes())
found = False
for group in config['TestConfigurations']:
    for target in group['TestTargets']:
        if target['BlueprintName'] != 'HistoryLibTests':
            continue
        found = True
        target.setdefault('EnvironmentVariables', {})['HISTORYLIB_TESTING'] = 'unit'
        target['CommandLineArguments'] = [
            '-enable_icloud_sync', 'NO', '-persistence_launch_icloud_enabled', 'NO',
            '-show_site_icons', 'NO',
        ]
if not found:
    raise SystemExit('No hosted unit-test target found; refusing to launch a normal app store.')
(products / 'HistoryLib_UnitOnly.xctestrun').write_bytes(plistlib.dumps(config))
PY
xcodebuild test-without-building \
  -xctestrun "$test_derived_data/Build/Products/HistoryLib_UnitOnly.xctestrun" \
  -destination "$test_destination" -parallel-testing-enabled NO \
  -only-testing:HistoryLibTests
