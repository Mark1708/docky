# Unsigned preview releases

Docky preview releases provide a testable DMG before the fork has a Developer ID Application certificate. They are ad-hoc signed, not notarized, published as GitHub prereleases, and never participate in the stable Sparkle channel.

User installation and verification instructions are in [preview-installation.md](preview-installation.md). The same file is included in the DMG and used as the GitHub prerelease notes.

## Contract

| Field | Format | Example |
|---|---|---|
| Git tag | `preview-vX.Y.Z.N` | `preview-v0.10.0.1` |
| Marketing version | `X.Y.Z` | `0.10.0` |
| Preview number | positive integer `N` without leading zeroes | `1` |
| Build version | UTC `YYYYMMDDHHmm` | `202610221430` |
| DMG | `Docky-X.Y.Z-preview.N-BUILD.dmg` | `Docky-0.10.0-preview.1-202610221430.dmg` |

The `preview-` prefix deliberately does not match the stable release trigger `v*.*.*`. The stable `v0.10.0` tag remains reserved for a Developer ID-signed and notarized release.

Each preview bundle must satisfy these invariants:

- both Docky and the embedded Watchdog are universal `arm64` + `x86_64` binaries;
- both bundles have the same marketing and build versions;
- both bundles are ad-hoc signed and pass strict nested `codesign` verification;
- the main app carries `disable-library-validation` so its ad-hoc signed embedded frameworks can load;
- neither bundle carries the development-only `get-task-allow` entitlement;
- Gatekeeper assessment does not report the preview as accepted;
- `DockyUpdatesEnabled=NO`;
- `SUFeedURL` and `SUPublicEDKey` are empty;
- no provisioning profile is embedded;
- the DMG contains `Docky.app`, an `/Applications` symlink, and `INSTALL.md`;
- the published DMG has a SHA-256 checksum and GitHub artifact attestation.

## Publish a preview

Start only from a green commit already merged into `main`:

```sh
git switch main
git pull --ff-only origin main
git status --short

git tag -a preview-v0.10.0.1 -m "Docky 0.10.0 Preview 1"
git push origin preview-v0.10.0.1

gh workflow run preview-release.yml \
  --repo Mark1708/docky \
  --ref main \
  -f preview_tag=preview-v0.10.0.1
```

`--ref main` selects the reviewed workflow definition from the default branch. The workflow independently checks out the requested tag and rejects it unless that exact commit belongs to `origin/main` and no GitHub Release already exists for the tag.

The workflow:

1. validates the tag, main ancestry, build floor, and release state;
2. builds a universal Release app with ad-hoc signing and updates disabled;
3. verifies bundle identifiers, versions, signatures, architectures, update settings, and required preview entitlements;
4. launches the built app in test mode and fails if it exits during startup;
5. creates and remounts the DMG, then verifies its contents;
6. writes `SHA256SUMS` and creates a GitHub provenance attestation for the DMG;
7. uploads an intermediate Actions artifact;
8. rechecks the checksum on a separate Linux publish job;
9. creates a draft and converts it to a non-latest GitHub prerelease.

The workflow uses no Apple, notarization, Developer ID, or Sparkle private-key secrets.

## Verify a published preview

```sh
mkdir Docky-preview && cd Docky-preview
gh release download preview-v0.10.0.1 --repo Mark1708/docky
shasum -a 256 -c SHA256SUMS
gh attestation verify Docky-*.dmg --repo Mark1708/docky
```

Test installation on a clean or secondary macOS account. Verify the actual executable path, the Privacy & Security → Open Anyway flow, Accessibility and Screen Recording prompts, fan layout, folder backdrop, and application restart. Automatic update controls must remain disabled.

## Failure and replacement policy

- Before publication, a failed publish job removes only its unpublished draft.
- Never reuse or replace assets for a published preview tag.
- If a published preview is defective, leave it marked as a prerelease and publish `preview-vX.Y.Z.(N+1)` from a new commit.
- Do not upload `appcast.xml` to a preview release and do not mark it as latest.
- Do not weaken `.github/workflows/release.yml`; stable releases continue to require Developer ID, notarization, stapling, and Sparkle signatures.
