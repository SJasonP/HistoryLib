#!/usr/bin/env python3
"""Validate HistoryLib localization coverage and format placeholders."""

from __future__ import annotations

import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ANDROID_RES = ROOT / "platforms/android/app/src/main/res"
APPLE_ROOT = ROOT / "platforms/apple/HistoryLib"
WINDOWS_RES = ROOT / "platforms/windows/Resources"
ANDROID_LOCALES = ("en-rUS", "zh-rCN", "ar", "fr", "ru", "es")
APPLE_LOCALES = ("en-US", "zh-Hans", "ar", "fr", "ru", "es")
WINDOWS_LOCALES = ("en-US", "zh-Hans", "ar", "fr", "ru", "es")
ANDROID_PLURAL_QUANTITIES = {
    "en-rUS": {"one", "other"},
    "zh-rCN": {"other"},
    "ar": {"zero", "one", "two", "few", "many", "other"},
    "fr": {"one", "many", "other"},
    "ru": {"one", "few", "many", "other"},
    "es": {"one", "many", "other"},
}
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(lld|ld|llu|lu|[a-zA-Z@])")
INVARIANT_TERMS = (
    "HistoryLib",
    "Safari",
    "Google Takeout",
    "Chrome",
    "iCloud",
    "CloudKit",
    "Android",
    "Windows",
    "macOS",
    "iOS",
    ".hlz",
    ".zip",
    ".json",
    "ZIP",
    "JSON",
    "URL",
    "HH:mm:ss",
    "yyyy-MM-dd",
)


def placeholders(value: str) -> Counter[str]:
    return Counter(PLACEHOLDER_RE.findall(value))


def xml_strings(path: Path) -> dict[str, str]:
    root = ET.parse(path).getroot()
    return {
        item.attrib["name"]: item.findtext("value", default="")
        if item.tag == "data"
        else item.text or ""
        for item in root
        if item.tag in {"string", "data"}
    }


def xml_plurals(path: Path) -> dict[str, dict[str, str]]:
    root = ET.parse(path).getroot()
    return {
        plural.attrib["name"]: {
            item.attrib["quantity"]: item.text or ""
            for item in plural.findall("item")
        }
        for plural in root.findall("plurals")
    }


def require_same(source: dict[str, str], translated: dict[str, str], label: str) -> list[str]:
    errors: list[str] = []
    if source.keys() != translated.keys():
        missing = sorted(source.keys() - translated.keys())
        extra = sorted(translated.keys() - source.keys())
        errors.append(f"{label}: key mismatch; missing={missing}, extra={extra}")
    for key in source.keys() & translated.keys():
        if not translated[key].strip():
            errors.append(f"{label}: empty translation for {key}")
        if placeholders(source[key]) != placeholders(translated[key]):
            errors.append(f"{label}: placeholder mismatch for {key}")
        for term in INVARIANT_TERMS:
            is_takeout_equivalent = (
                term == "Chrome"
                and "Chrome Takeout" in source[key]
                and "Google Takeout" in translated[key]
            )
            if term in source[key] and term not in translated[key] and not is_takeout_equivalent:
                errors.append(f"{label}: lost invariant term {term!r} for {key}")
    return errors


def validate() -> list[str]:
    errors: list[str] = []
    android_source = xml_strings(ANDROID_RES / "values/strings.xml")
    android_source_plurals = xml_plurals(ANDROID_RES / "values/strings.xml")
    for locale in ANDROID_LOCALES:
        path = ANDROID_RES / f"values-{locale}/strings.xml"
        translated = xml_strings(path)
        errors.extend(require_same(android_source, translated, f"Android {locale}"))
        translated_plurals = xml_plurals(path)
        if translated_plurals.keys() != android_source_plurals.keys():
            errors.append(f"Android {locale}: plural resource key mismatch")
        for name, forms in translated_plurals.items():
            if forms.keys() != ANDROID_PLURAL_QUANTITIES[locale]:
                errors.append(f"Android {locale}: incorrect plural quantities for {name}")
            if any(not value.strip() for value in forms.values()):
                errors.append(f"Android {locale}: empty plural form for {name}")

    catalog = json.loads((APPLE_ROOT / "Localizable.xcstrings").read_text(encoding="utf-8"))
    for source, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or not source.strip():
            continue
        for locale in APPLE_LOCALES:
            localization = entry.get("localizations", {}).get(locale, {})
            plural = localization.get("variations", {}).get("plural")
            if plural:
                expected = {"one", "many", "other"} if locale in {"fr", "es"} else {"one", "other"}
                if plural.keys() != expected:
                    errors.append(f"Apple {locale}: incorrect plural quantities for {source!r}")
                for quantity, variation in plural.items():
                    value = variation.get("stringUnit", {}).get("value")
                    if not value:
                        errors.append(
                            f"Apple {locale}: empty {quantity} plural for {source!r}"
                        )
                    elif placeholders(source) != placeholders(value):
                        errors.append(
                            f"Apple {locale}: placeholder mismatch in {quantity} plural for {source!r}"
                        )
                continue
            value = localization.get("stringUnit", {}).get("value")
            if not value:
                errors.append(f"Apple {locale}: missing translation for {source!r}")
            elif placeholders(source) != placeholders(value):
                errors.append(f"Apple {locale}: placeholder mismatch for {source!r}")
            else:
                for term in INVARIANT_TERMS:
                    if term in source and term not in value:
                        errors.append(
                            f"Apple {locale}: lost invariant term {term!r} for {source!r}"
                        )

    settings_source = xml_strings_from_strings_file(
        APPLE_ROOT / "Settings.bundle/en.lproj/Root.strings"
    )
    for locale in APPLE_LOCALES:
        translated = xml_strings_from_strings_file(
            APPLE_ROOT / f"Settings.bundle/{locale}.lproj/Root.strings"
        )
        errors.extend(require_same(settings_source, translated, f"Apple Settings {locale}"))

    windows_plural_keys = {
        f"{name}.{quantity.title()}"
        for name in android_source_plurals
        for quantity in ("zero", "one", "two", "few", "many", "other")
    }
    windows_expected_keys = android_source.keys() | windows_plural_keys
    for locale in WINDOWS_LOCALES:
        translated = xml_strings(WINDOWS_RES / locale / "Resources.resw")
        if translated.keys() != windows_expected_keys:
            errors.append(f"Windows {locale}: resource key mismatch")
        if any(not value.strip() for value in translated.values()):
            errors.append(f"Windows {locale}: empty resource value")

    with (APPLE_ROOT / "Info.plist").open("rb") as stream:
        declared = set(plistlib.load(stream).get("CFBundleLocalizations", []))
    if not set(APPLE_LOCALES).issubset(declared):
        errors.append("Apple Info.plist does not declare every supported locale")

    manifest = (ROOT / "platforms/android/app/src/main/AndroidManifest.xml").read_text()
    if 'android:supportsRtl="true"' not in manifest:
        errors.append("Android manifest must enable RTL support")
    locale_root = ET.parse(ANDROID_RES / "xml/locales_config.xml").getroot()
    android_name = "{http://schemas.android.com/apk/res/android}name"
    declared_locales = {item.attrib[android_name] for item in locale_root.findall("locale")}
    expected_locales = {"en-US", "zh-CN", "ar", "fr", "ru", "es"}
    if declared_locales != expected_locales:
        errors.append("Android locale config must declare exactly the six product locales")
    return errors


def xml_strings_from_strings_file(path: Path) -> dict[str, str]:
    rows: dict[str, str] = {}
    pattern = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";\s*$')
    for line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(line)
        if match:
            rows[match.group(1)] = match.group(2)
    return rows


if __name__ == "__main__":
    failures = validate()
    if failures:
        print("\n".join(failures), file=sys.stderr)
        raise SystemExit(1)
    print("Localization validation passed for all six product languages.")
