# Contributing to Docky

Thanks for your interest in improving Docky. Contributions of all kinds are
welcome: bug reports, fixes, features, and documentation.

## Community

This repository is the `Mark1708/docky` fork. The
[Docky Discord](https://discord.gg/vAwVNtPSgE) and
[Jose Quintero's sponsorship page](https://github.com/sponsors/josejuanqm)
belong to and support the upstream project.

## Reporting issues

Open fork issues at https://github.com/Mark1708/docky/issues. Helpful reports
include:

- macOS version and Mac model
- Docky version (Settings shows the build)
- Steps to reproduce
- A diagnostic bundle: Settings -> Feedback builds one and reveals it in Finder,
  so you can attach it to the issue.

## Development setup

1. Clone `https://github.com/Mark1708/docky.git`.
2. Open `Docky.xcodeproj` in Xcode 16 or later.
3. Build and run the `Docky` scheme.

The project uses Xcode's file-system-synchronized groups, so new source files
under `Docky/` are picked up automatically without editing the project file.

## Pull requests

- Branch off `main` and keep changes focused.
- Match the surrounding code style; Docky leans on AppKit + SwiftUI and uses
  explanatory comments only where the reasoning is non-obvious (for example, the
  private-API usage in `Docky/Private/`).
- Run the localization validator, release-preflight fixtures, unsigned build,
  and app-hosted tests before opening a PR:

  ```sh
  python3 scripts/validate_localizations.py
  python3 -m unittest discover -s scripts/tests
  xcodebuild -project Docky.xcodeproj -scheme Docky \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO build
  DOCKY_TEST_MODE=1 xcodebuild -project Docky.xcodeproj -scheme Docky \
    -configuration Debug -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
  ```

- Describe what changed and why, and include before/after notes or screenshots
  for UI changes.

## Private APIs

Docky relies on private SkyLight / CoreGraphics Services and Accessibility SPI.
When touching `Docky/Private/`, document why a given call is needed and what
breaks without it, so the next reader understands the tradeoff.

## License

By contributing, you agree that your contributions are licensed under the
GNU General Public License v3.0, the same license that covers the project.
