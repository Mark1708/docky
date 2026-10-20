#!/usr/bin/env python3
"""Validate Docky's checked-in localization and fork-safety contracts."""

from __future__ import annotations

import base64
import binascii
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATHS = [ROOT / "Docky/Localizable.xcstrings", ROOT / "Docky/MenuCatalog.xcstrings"]
MACHINE_TOKEN_ALLOWLIST = {
    "AppleScript",
    "Docky",
    "Finder",
    "Firefox",
    "GitHub",
    "JSON",
    "Launchpad",
    "Safari",
    "SHA-256",
    "URL",
    "Xcode",
}
PRIVACY_KEYS = {
    "NSAppleEventsUsageDescription",
    "NSCalendarsFullAccessUsageDescription",
    "NSCalendarsUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSRemindersFullAccessUsageDescription",
    "NSRemindersUsageDescription",
}
PRINTF_PATTERN = re.compile(
    r"%(?P<position>\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?:hh|h|ll|l|L|z|t|j)?(?P<conversion>[@diuoxXfFeEgGaAcCsSp])"
)
STRINGS_LINE_PATTERN = re.compile(r'^\s*"(?P<key>(?:\\.|[^"\\])*)"\s*=\s*"(?P<value>(?:\\.|[^"\\])*)"\s*;\s*$')


class ValidationErrors:
    def __init__(self) -> None:
        self.messages: list[str] = []

    def add(self, message: str) -> None:
        self.messages.append(message)

    def require(self, condition: bool, message: str) -> None:
        if not condition:
            self.add(message)


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def is_active(entry: dict[str, Any]) -> bool:
    state = entry.get("extractionState")
    return state is None or state in {"manual", "new"}


def string_unit_values(value: Any) -> list[str]:
    values: list[str] = []
    if isinstance(value, dict):
        string_unit = value.get("stringUnit")
        if isinstance(string_unit, dict) and isinstance(string_unit.get("value"), str):
            values.append(string_unit["value"])
        for key, child in value.items():
            if key != "stringUnit":
                values.extend(string_unit_values(child))
    elif isinstance(value, list):
        for child in value:
            values.extend(string_unit_values(child))
    return values


def printf_signature(value: str) -> tuple[tuple[int, str], ...]:
    signature: list[tuple[int, str]] = []
    implicit_position = 1
    index = 0
    while index < len(value):
        if value[index] != "%":
            index += 1
            continue
        if index + 1 < len(value) and value[index + 1] == "%":
            index += 2
            continue
        if index + 1 < len(value) and value[index + 1].isspace():
            index += 1
            continue
        match = PRINTF_PATTERN.match(value, index)
        if match is None:
            index += 1
            continue
        raw_position = match.group("position")
        position = int(raw_position[:-1]) if raw_position else implicit_position
        if raw_position is None:
            implicit_position += 1
        signature.append((position, match.group("conversion")))
        index = match.end()
    return tuple(sorted(signature))


def validate_catalog(path: Path, errors: ValidationErrors) -> tuple[dict[str, Any], int]:
    document = load_json(path)
    strings = document.get("strings")
    if not isinstance(strings, dict):
        errors.add(f"{path.relative_to(ROOT)}: missing strings dictionary")
        return {}, 0

    active_count = 0
    for key, entry in strings.items():
        if not isinstance(entry, dict) or not is_active(entry):
            continue
        active_count += 1
        localizations = entry.get("localizations", {})
        russian = localizations.get("ru") if isinstance(localizations, dict) else None
        russian_values = string_unit_values(russian)
        if key not in MACHINE_TOKEN_ALLOWLIST and (not russian_values or any(not value.strip() for value in russian_values)):
            errors.add(f"{path.relative_to(ROOT)}: active key {key!r} has no complete Russian translation")
            continue

        source = localizations.get("en") if isinstance(localizations, dict) else None
        source_values = string_unit_values(source) or [key]
        source_signatures = {printf_signature(value) for value in source_values}
        for value in russian_values:
            signature = printf_signature(value)
            if signature not in source_signatures:
                errors.add(
                    f"{path.relative_to(ROOT)}: printf signature mismatch for {key!r}: "
                    f"source={sorted(source_signatures)!r}, ru={signature!r}"
                )
    return strings, active_count


def collect_menu_keys(value: Any) -> set[str]:
    keys: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key.endswith("LocalizationKey") and isinstance(child, str) and child:
                keys.add(child)
            keys.update(collect_menu_keys(child))
    elif isinstance(value, list):
        for child in value:
            keys.update(collect_menu_keys(child))
    return keys


def parse_strings_file(path: Path, errors: ValidationErrors) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("/*") or stripped.startswith("//"):
            continue
        match = STRINGS_LINE_PATTERN.match(line)
        if match is None:
            errors.add(f"{path.relative_to(ROOT)}:{line_number}: malformed .strings entry")
            continue
        result[match.group("key")] = match.group("value")
    return result


def version_tuple(value: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in value.split("."))
    except ValueError as error:
        raise ValueError(f"invalid semantic version {value!r}") from error


def validate_menu_catalog(menu_strings: dict[str, Any], errors: ValidationErrors) -> None:
    actions = load_json(ROOT / "Docky/MenuCatalog/actions.json")
    menus = load_json(ROOT / "Docky/MenuCatalog/menus.json")
    required_keys = collect_menu_keys(actions) | collect_menu_keys(menus)
    missing = sorted(required_keys - set(menu_strings))
    for key in missing:
        errors.add(f"Docky/MenuCatalog.xcstrings: missing JSON localization key {key!r}")


def validate_info_plist_strings(errors: ValidationErrors) -> None:
    for language in ("en", "ru"):
        path = ROOT / f"Config/{language}.lproj/InfoPlist.strings"
        errors.require(path.is_file(), f"{path.relative_to(ROOT)}: missing privacy localization resource")
        if not path.is_file():
            continue
        values = parse_strings_file(path, errors)
        for key in sorted(PRIVACY_KEYS):
            errors.require(bool(values.get(key, "").strip()), f"{path.relative_to(ROOT)}: missing non-empty {key}")


def validate_project_configuration(errors: ValidationErrors) -> None:
    project_path = ROOT / "Docky.xcodeproj/project.pbxproj"
    project = project_path.read_text(encoding="utf-8")
    known_regions_match = re.search(r"knownRegions = \((?P<body>.*?)\);", project, re.DOTALL)
    known_regions = set(re.findall(r"\b(?:Base|[a-z]{2})\b", known_regions_match.group("body") if known_regions_match else ""))
    errors.require({"Base", "en", "es", "ru"}.issubset(known_regions), "project.pbxproj: knownRegions must include Base, en, es, and ru")

    for path in (
        ROOT / "Docky/Base.lproj/MainMenu.xib",
        ROOT / "Docky/en.lproj/MainMenu.strings",
        ROOT / "Docky/es.lproj/MainMenu.strings",
        ROOT / "Docky/ru.lproj/MainMenu.strings",
    ):
        if path.name == "MainMenu.strings" and "en.lproj" in str(path):
            continue
        errors.require(path.is_file() and path.stat().st_size > 0, f"{path.relative_to(ROOT)}: missing MainMenu localization resource")

    for setting in ("DOCKY_UPDATE_FEED_URL", "DOCKY_SPARKLE_PUBLIC_KEY", "DEVELOPMENT_TEAM"):
        values = re.findall(rf"\b{setting}\s*=\s*([^;]*);", project)
        errors.require(all(value.strip() in {'', '""'} for value in values), f"project.pbxproj: {setting} must have no checked-in value")
    errors.require("https://getdocky.com/releases" not in project, "project.pbxproj: upstream update feed must not be present")


def validate_sparkle_version(errors: ValidationErrors) -> None:
    resolved = load_json(ROOT / "Docky.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
    versions = [
        pin.get("state", {}).get("version")
        for pin in resolved.get("pins", [])
        if pin.get("identity") == "sparkle"
    ]
    errors.require(len(versions) == 1 and isinstance(versions[0], str), "Package.resolved: expected one resolved Sparkle version")
    if len(versions) == 1 and isinstance(versions[0], str):
        try:
            errors.require(version_tuple(versions[0]) >= (2, 10, 0), f"Package.resolved: Sparkle {versions[0]} is older than 2.10.0")
        except ValueError as error:
            errors.add(f"Package.resolved: {error}")


def validate_sparkle_public_key(errors: ValidationErrors) -> None:
    public_key_path = ROOT / "Config/SparklePublicKey.txt"
    errors.require(public_key_path.is_file(), "Config/SparklePublicKey.txt: missing fork Sparkle public key")
    if not public_key_path.is_file():
        return
    public_key = public_key_path.read_text(encoding="utf-8").strip()
    try:
        decoded_key = base64.b64decode(public_key, validate=True)
    except (binascii.Error, ValueError):
        errors.add("Config/SparklePublicKey.txt: invalid base64 public key")
        return
    errors.require(len(decoded_key) == 32, "Config/SparklePublicKey.txt: Ed25519 public key must decode to 32 bytes")


def main() -> int:
    errors = ValidationErrors()
    catalogs: dict[Path, dict[str, Any]] = {}
    active_total = 0
    for path in CATALOG_PATHS:
        strings, active_count = validate_catalog(path, errors)
        catalogs[path] = strings
        active_total += active_count

    validate_menu_catalog(catalogs[ROOT / "Docky/MenuCatalog.xcstrings"], errors)
    validate_info_plist_strings(errors)
    validate_project_configuration(errors)
    validate_sparkle_version(errors)
    validate_sparkle_public_key(errors)

    if errors.messages:
        for message in errors.messages:
            print(f"error: {message}", file=sys.stderr)
        print(f"Localization validation failed with {len(errors.messages)} error(s).", file=sys.stderr)
        return 1

    print(f"Localization validation passed: {active_total} active catalog keys, Russian coverage complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
