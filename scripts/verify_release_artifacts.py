#!/usr/bin/env python3
"""Verify immutable Docky release archive metadata in a Sparkle appcast."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NAMESPACE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
SPARKLE_VERSION = f"{{{SPARKLE_NAMESPACE}}}version"
SPARKLE_SHORT_VERSION = f"{{{SPARKLE_NAMESPACE}}}shortVersionString"
SPARKLE_SIGNATURE = f"{{{SPARKLE_NAMESPACE}}}edSignature"


class VerificationError(RuntimeError):
    pass


def verify(
    *,
    release_tag: str,
    marketing_version: str,
    build_version: str,
    archive: Path,
    appcast: Path,
) -> str:
    if release_tag != f"v{marketing_version}":
        raise VerificationError("release tag and marketing version differ")
    if not archive.is_file():
        raise VerificationError(f"release archive is missing: {archive}")
    try:
        root = ET.parse(appcast).getroot()
    except (ET.ParseError, OSError) as error:
        raise VerificationError(f"could not parse appcast: {error}") from error

    enclosures = root.findall(".//enclosure")
    if len(enclosures) != 1:
        raise VerificationError(f"appcast must contain exactly one enclosure; found {len(enclosures)}")
    enclosure = enclosures[0]
    expected_url = f"https://github.com/Mark1708/docky/releases/download/{release_tag}/{archive.name}"
    checks = {
        "url": (enclosure.attrib.get("url"), expected_url),
        "sparkle:version": (enclosure.attrib.get(SPARKLE_VERSION), build_version),
        "sparkle:shortVersionString": (enclosure.attrib.get(SPARKLE_SHORT_VERSION), marketing_version),
        "length": (enclosure.attrib.get("length"), str(archive.stat().st_size)),
    }
    for label, (actual, expected) in checks.items():
        if actual != expected:
            raise VerificationError(f"appcast {label} is {actual!r}; expected {expected!r}")

    signature = enclosure.attrib.get(SPARKLE_SIGNATURE, "").strip()
    if not signature:
        raise VerificationError("appcast enclosure has no EdDSA signature")
    return signature


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-version", required=True)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--appcast", required=True, type=Path)
    parser.add_argument("--print-signature", action="store_true")
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        signature = verify(
            release_tag=arguments.release_tag,
            marketing_version=arguments.marketing_version,
            build_version=arguments.build_version,
            archive=arguments.archive,
            appcast=arguments.appcast,
        )
    except VerificationError as error:
        print(f"release artifact verification failed: {error}", file=sys.stderr)
        return 1
    if arguments.print_signature:
        print(signature)
    else:
        print("Release artifact verification passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
