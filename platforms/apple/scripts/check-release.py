#!/usr/bin/env python3
"""Check an Apple Release app before audit/distribution; does not sign or publish."""
import argparse
import json
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('app', type=Path)
parser.add_argument('--minimum-build', type=int, default=8)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
app = args.app.resolve()
is_mac = (app / 'Contents').is_dir()
resources = app / 'Contents/Resources' if is_mac else app
info_path = app / 'Contents/Info.plist' if is_mac else app / 'Info.plist'
info = plistlib.loads(info_path.read_bytes())
expected = (root / 'VERSION').read_text().strip()
assert info['CFBundleIdentifier'] == 'com.SJasonP.HistoryLib', 'App identity changed'
assert info['CFBundleShortVersionString'] == expected, 'Product version mismatch'
assert int(info['CFBundleVersion']) >= args.minimum_build, 'Build number is too low'
minimum_os = info.get('LSMinimumSystemVersion') if is_mac else info.get('MinimumOSVersion')
assert minimum_os == '26.0', f'Unexpected deployment baseline: {minimum_os}'
locales = {'en-US', 'zh-Hans', 'ar', 'fr', 'ru', 'es'}
assert locales <= set(info['CFBundleLocalizations']), 'Missing product locales'
if is_mac:
    assert info.get('NSIsTouchNative') is True, 'Touch on Mac support is not declared'

privacy = plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes())
assert privacy['NSPrivacyTracking'] is False
assert privacy['NSPrivacyCollectedDataTypes'] == []
reasons = {entry['NSPrivacyAccessedAPIType']: set(entry['NSPrivacyAccessedAPITypeReasons'])
           for entry in privacy['NSPrivacyAccessedAPITypes']}
assert reasons['NSPrivacyAccessedAPICategoryUserDefaults'] == {'CA92.1'}
assert reasons['NSPrivacyAccessedAPICategoryFileTimestamp'] == {'C617.1', '3B52.1'}
assert reasons['NSPrivacyAccessedAPICategoryDiskSpace'] == {'E174.1'}

metadata = json.loads((resources / 'Metadata.appintents/extract.actionsdata').read_text())
expected_intents = {'SearchHistoryIntent', 'PrepareNaturalHistorySearchIntent', 'SearchHistoryWithSiriIntent'}
assert set(metadata['actions']) == expected_intents, 'Unexpected exported action surface'
for name, action in metadata['actions'].items():
    assert action['openAppWhenRun'] is True, f'{name} does not open the app'
    assert action['authenticationPolicy'] == 2, f'{name} lacks local authentication'
assert not metadata['entities'], 'Unexpected system history entities'
for locale in locales:
    localized = resources / (locale + '.lproj')
    assert (localized / 'AppShortcuts.strings').is_file(), f'Missing shortcut strings: {locale}'
    if not is_mac:
        assert (localized / 'nlu.appintents').is_dir(), f'Missing compiled shortcut model: {locale}'

binary = app / 'Contents/MacOS' / info['CFBundleExecutable'] if is_mac else app / info['CFBundleExecutable']
contents = binary.read_bytes()
for marker in (b'HISTORYLIB_TESTING', b'HISTORYLIB_UI_TESTING', b'synthetic-ui-fixture'):
    assert marker not in contents, f'Debug test marker in Release: {marker!r}'
print(f"{'macOS' if is_mac else 'iOS'} {expected} ({info['CFBundleVersion']}): Release structure, privacy manifest, six locales, and intents passed.")
print('Distribution signing, CloudKit production readiness, store validation, and human acceptance remain separate checks.')
