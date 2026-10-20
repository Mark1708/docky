from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from verify_release_artifacts import VerificationError, verify


class ReleaseArtifactVerificationTests(unittest.TestCase):
    def test_exact_single_enclosure_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            archive, appcast = self.fixture(Path(directory))
            signature = verify(
                release_tag="v0.10.1",
                marketing_version="0.10.1",
                build_version="202610220900",
                archive=archive,
                appcast=appcast,
            )
            self.assertEqual(signature, "test-signature")

    def test_mutable_or_duplicate_enclosure_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive, appcast = self.fixture(root, url="https://github.com/Mark1708/docky/releases/latest/download/Docky.zip")
            with self.assertRaisesRegex(VerificationError, "appcast url"):
                verify(
                    release_tag="v0.10.1",
                    marketing_version="0.10.1",
                    build_version="202610220900",
                    archive=archive,
                    appcast=appcast,
                )

            archive, appcast = self.fixture(root, duplicate=True)
            with self.assertRaisesRegex(VerificationError, "exactly one enclosure"):
                verify(
                    release_tag="v0.10.1",
                    marketing_version="0.10.1",
                    build_version="202610220900",
                    archive=archive,
                    appcast=appcast,
                )

    def fixture(
        self,
        root: Path,
        *,
        url: str | None = None,
        duplicate: bool = False,
    ) -> tuple[Path, Path]:
        archive = root / "Docky-0.10.1-202610220900.zip"
        archive.write_bytes(b"release archive")
        enclosure_url = url or (
            "https://github.com/Mark1708/docky/releases/download/"
            "v0.10.1/Docky-0.10.1-202610220900.zip"
        )
        enclosure = (
            f'<enclosure url="{enclosure_url}" length="{archive.stat().st_size}" '
            'sparkle:version="202610220900" sparkle:shortVersionString="0.10.1" '
            'sparkle:edSignature="test-signature" />'
        )
        appcast = root / "appcast.xml"
        appcast.write_text(
            '<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f"<channel><item>{enclosure}</item>"
            f"{'<item>' + enclosure + '</item>' if duplicate else ''}</channel></rss>",
            encoding="utf-8",
        )
        return archive, appcast


if __name__ == "__main__":
    unittest.main()
