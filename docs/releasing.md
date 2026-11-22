# Releasing Macros

Versions live only in git tags (`vX.Y.Z`). The `MARKETING_VERSION` in `apps/mac/project.yml` is a placeholder for
local builds.

## Cutting a release

Run the **Release** workflow from `main`: Actions → Release → Run workflow, or

```sh
gh workflow run release.yml -f version-bump-type=minor
```

It then:

1. runs CI (lint, tests, unsigned build) via `ci.yml`
2. computes the next version from the latest `vX.Y.Z` tag with
   [`wuguishifu/version-bump-workflow`](https://github.com/wuguishifu/version-bump-workflow). With no tags yet, it bumps
   from `0.0.0`, so `minor` gives `v0.1.0`.
3. on `macos-26`: imports the Developer ID certificate into a temporary keychain, then runs `pnpm nx run mac:release`
   with `VERSION` from the tag and `BUILD_NUMBER` = the workflow run number. That archives, exports, notarizes and
   staples the app, then builds, signs, notarizes and staples the DMG.
4. creates the `vX.Y.Z` GitHub release with generated notes, attaching `Macros-X.Y.Z.dmg` and `Macros-X.Y.Z.zip`

The signing secrets are only available to the macOS build job. Only the release job, which never sees them, has
`contents: write`.

## Repository secrets

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application certificate and private key, exported as `.p12`, base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `NOTARY_API_KEY_P8` | Contents of the App Store Connect API key (`AuthKey_….p8`) |
| `NOTARY_API_KEY_ID` | The API key's ID |
| `NOTARY_API_ISSUER_ID` | The API key's issuer ID (UUID) |

Set them with the GitHub CLI (each command reads the value locally, so nothing is echoed):

```sh
base64 -i /path/to/DeveloperID.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64
gh secret set MACOS_CERTIFICATE_PASSWORD          # prompts
gh secret set NOTARY_API_KEY_P8 < /path/to/AuthKey_XXXXXXXXXX.p8
gh secret set NOTARY_API_KEY_ID --body XXXXXXXXXX
gh secret set NOTARY_API_ISSUER_ID --body xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

When the certificate is renewed (the current one expires 2027-02-01), update the first two secrets.

## Local release

`pnpm nx run mac:release` does the same thing on your Mac, using the `macros-notary` notarytool keychain profile.
Pass `VERSION=X.Y.Z` (and optionally `BUILD_NUMBER`) to set the version. Output goes to `dist/apps/mac/release/`.
