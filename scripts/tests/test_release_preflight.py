from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from release_preflight import PreflightError, validate_preflight


VALID_APPCAST = b"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel><item><enclosure url="https://example.invalid/Docky.zip"
    sparkle:version="202610210900" sparkle:shortVersionString="0.10.0" /></item></channel>
</rss>
"""


class ReleasePreflightTests(unittest.TestCase):
    def defaults(self, **overrides: object) -> dict[str, object]:
        values: dict[str, object] = {
            "release_tag": "v0.10.1",
            "build_version": "202610220900",
            "checked_out_commit": "abc123",
            "tag_commit": "abc123",
            "main_is_ancestor": True,
            "release_state": None,
            "has_any_release": True,
            "latest_appcast": VALID_APPCAST,
            "latest_appcast_error": None,
        }
        values.update(overrides)
        return values

    def test_initial_release_requires_absent_release_and_appcast(self) -> None:
        result = validate_preflight(**self.defaults(
            release_tag="v0.10.0",
            build_version="202610020902",
            has_any_release=False,
            latest_appcast=None,
        ))
        self.assertEqual(result.marketing_version, "0.10.0")
        self.assertEqual(result.build_version, 202610020902)

    def test_later_release_accepts_valid_latest_appcast(self) -> None:
        result = validate_preflight(**self.defaults())
        self.assertEqual(result.marketing_version, "0.10.1")

    def test_later_release_rejects_malformed_or_unreachable_appcast(self) -> None:
        with self.subTest("malformed"):
            with self.assertRaisesRegex(PreflightError, "malformed XML"):
                validate_preflight(**self.defaults(latest_appcast=b"not xml"))
        with self.subTest("unreachable"):
            with self.assertRaisesRegex(PreflightError, "unavailable"):
                validate_preflight(**self.defaults(
                    latest_appcast=None,
                    latest_appcast_error="network timeout",
                ))

    def test_existing_draft_or_published_release_is_rejected(self) -> None:
        for state in ("draft", "published"):
            with self.subTest(state):
                with self.assertRaisesRegex(PreflightError, "already exists"):
                    validate_preflight(**self.defaults(release_state=state))

    def test_reused_or_lower_build_is_rejected(self) -> None:
        for build in ("202610210900", "202610210899"):
            with self.subTest(build):
                with self.assertRaisesRegex(PreflightError, "greater than latest"):
                    validate_preflight(**self.defaults(build_version=build))

    def test_initial_floor_is_strict(self) -> None:
        with self.assertRaisesRegex(PreflightError, "greater than initial floor"):
            validate_preflight(**self.defaults(
                release_tag="v0.10.0",
                build_version="202610020901",
                has_any_release=False,
                latest_appcast=None,
            ))

    def test_tag_and_commit_mismatches_are_rejected(self) -> None:
        with self.subTest("tag format"):
            with self.assertRaisesRegex(PreflightError, "vX.Y.Z"):
                validate_preflight(**self.defaults(release_tag="0.10.1"))
        with self.subTest("tag commit"):
            with self.assertRaisesRegex(PreflightError, "checked-out commit"):
                validate_preflight(**self.defaults(tag_commit="def456"))
        with self.subTest("main ancestry"):
            with self.assertRaisesRegex(PreflightError, "origin/main"):
                validate_preflight(**self.defaults(main_is_ancestor=False))


if __name__ == "__main__":
    unittest.main()
