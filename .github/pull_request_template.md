## Summary

<!-- What does this PR do and why? Keep it short. -->

## Type of change

<!-- Mark the relevant option(s) with an "x". -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that changes existing behavior)
- [ ] Refactor / performance (no functional change)
- [ ] Documentation
- [ ] Build / tooling / CI

## Related issues

<!-- Link issues this PR addresses, e.g. "Closes #123". -->

## How was this tested?

<!-- Describe how you verified the change. -->

- macOS version:
- Xcode version:
- Steps to reproduce / verify:

## Screenshots / recordings

<!-- For UI changes, add before/after screenshots or a short screen recording. -->

## Checklist

- [ ] `python3 scripts/validate_localizations.py` passes.
- [ ] `python3 -m unittest discover -s scripts/tests` passes.
- [ ] The unsigned Debug build passes: `xcodebuild -project Docky.xcodeproj -scheme Docky -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- [ ] App-hosted tests pass: `DOCKY_TEST_MODE=1 xcodebuild -project Docky.xcodeproj -scheme Docky -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test`.
- [ ] I tested the changed runtime behavior on macOS 14.0 or later.
- [ ] I granted/verified any required Accessibility and Screen Recording permissions where relevant.
- [ ] Commit messages follow the `type(scope): summary` convention used in this repo.
- [ ] I updated documentation (README, comments) where needed.
- [ ] My changes are licensed under GPLv3, consistent with the rest of the project.
