from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from preview_release_preflight import PreviewPreflightError, validate_preview_preflight


class PreviewReleasePreflightTests(unittest.TestCase):
    def defaults(self, **overrides: object) -> dict[str, object]:
        values: dict[str, object] = {
            "preview_tag": "preview-v0.10.0.1",
            "build_version": "202610220900",
            "checked_out_commit": "abc123",
            "tag_commit": "abc123",
            "main_is_ancestor": True,
            "release_state": None,
        }
        values.update(overrides)
        return values

    def test_accepts_isolated_preview_tag(self) -> None:
        result = validate_preview_preflight(**self.defaults())

        self.assertEqual(result.preview_tag, "preview-v0.10.0.1")
        self.assertEqual(result.marketing_version, "0.10.0")
        self.assertEqual(result.preview_number, 1)
        self.assertEqual(result.build_version, 202610220900)

    def test_rejects_non_preview_and_ambiguous_tags(self) -> None:
        for tag in ("v0.10.0", "preview-v0.10.0-1", "preview-v0.10.0.0", "preview-v0.10.0.01"):
            with self.subTest(tag):
                with self.assertRaisesRegex(PreviewPreflightError, "preview-vX.Y.Z.N"):
                    validate_preview_preflight(**self.defaults(preview_tag=tag))

    def test_rejects_non_numeric_or_old_build(self) -> None:
        for build in ("not-a-number", "202610020901"):
            with self.subTest(build):
                with self.assertRaises(PreviewPreflightError):
                    validate_preview_preflight(**self.defaults(build_version=build))

    def test_rejects_tag_commit_and_main_mismatches(self) -> None:
        with self.subTest("tag commit"):
            with self.assertRaisesRegex(PreviewPreflightError, "checked-out commit"):
                validate_preview_preflight(**self.defaults(tag_commit="def456"))
        with self.subTest("main ancestry"):
            with self.assertRaisesRegex(PreviewPreflightError, "origin/main"):
                validate_preview_preflight(**self.defaults(main_is_ancestor=False))

    def test_rejects_existing_release(self) -> None:
        for state in ("draft", "published"):
            with self.subTest(state):
                with self.assertRaisesRegex(PreviewPreflightError, "already exists"):
                    validate_preview_preflight(**self.defaults(release_state=state))


if __name__ == "__main__":
    unittest.main()
