# Release Pipeline

The release workflow builds a signed macOS archive, packages `MacOSUtilities.app`
into a DMG, notarizes and staples the DMG, then uploads the artifacts to a
GitHub Release.

## Required GitHub Secrets

- `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64`: base64 encoded `.p12` certificate that contains the Developer ID Application private key.
- `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD`: password for that `.p12` file.
- `MACOS_DEVELOPER_ID_APPLICATION`: optional full signing identity, such as `Developer ID Application: Your Name (TEAMID)`. If omitted, CI uses `Developer ID Application`.
- `APPLE_ID`: Apple ID email used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for the Apple ID.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `MACOS_BUNDLE_ID_PREFIX`: your private bundle prefix, for example `com.example`.

Create the certificate secret with:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

## Creating A Release

Push a tag:

```sh
git tag v1.0.0
git push origin v1.0.0
```

Or run **Release macOS app** manually from GitHub Actions and provide a tag.

The workflow publishes:

- `MacOSUtilities-<version>.dmg`
- `MacOSUtilities-<version>.dmg.sha256`
- `MacOSUtilities-<version>-dSYMs.zip`, when dSYMs are present

## Local Packaging Smoke Test

With a full Xcode install selected:

```sh
./scripts/build_release_dmg.sh
```

Set `CODE_SIGN_IDENTITY`, `BUNDLE_ID_PREFIX`, `DEVELOPMENT_TEAM`, `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`, and `NOTARIZE=true` to run the
same signed and notarized path locally.
