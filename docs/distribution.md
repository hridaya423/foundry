# Distribution & signing

The release workflow (`.github/workflows/release.yml`) publishes a signed,
notarized DMG whenever `VERSION` changes on `main`. If any signing secret is
missing, the workflow fails before it builds and publishes nothing, so the
site's download link never serves a build Gatekeeper blocks. Until the secrets
are set, publish by hand (below) and bump `VERSION` with `[skip ci]`.

The build is arm64 only (the `macos-26` runner is Apple silicon) and the app
declares macOS 14.0 as its minimum. The release text says both.

A commit message containing `[skip ci]` skips both workflows. Use it when you
publish a release by hand.

## One-time setup (requires an active paid Apple Developer membership)

1. **Create a Developer ID Application certificate**

   Xcode → Settings → Accounts → select the paid team → Manage Certificates →
   `+` → **Developer ID Application**. If the option is missing, the membership
   is expired or the account isn't Account Holder/Admin.

2. **Export the identity as a p12**

   ```sh
   security find-identity -v -p codesigning   # find "Developer ID Application: ..."
   security export -k login.keychain-db -t identities -f pkcs12 \
     -P "choose-a-p12-password" -o ~/DeveloperID.p12
   base64 -i ~/DeveloperID.p12 -o ~/DeveloperID.p12.b64
   ```

   Never put the certificate on the clipboard. Foundry's clipboard history can
   store it. Send the file to GitHub from the shell instead:

   ```sh
   gh secret set MACOS_DEVELOPER_ID_P12 < ~/DeveloperID.p12.b64
   rm -P ~/DeveloperID.p12 ~/DeveloperID.p12.b64
   ```

3. **Create an app-specific password** at <https://appleid.apple.com> →
   Sign-In and Security → App-Specific Passwords.

4. **Find the Team ID**: developer.apple.com → Membership details → Team ID.

5. **Set the other repository secrets** (`gh secret set NAME`, or github.com → repo →
   Settings → Secrets and variables → Actions → New repository secret). Type each
   value into the prompt rather than copying it:

   | Secret | Value |
   | --- | --- |
   | `MACOS_DEVELOPER_ID_P12` | the base64 p12 from step 2 (already set there) |
   | `MACOS_DEVELOPER_ID_P12_PASSWORD` | the p12 password |
   | `APPLE_ID` | the Apple ID email |
   | `APPLE_APP_PASSWORD` | the app-specific password |
   | `APPLE_TEAM_ID` | the 10-char team ID |

## Releasing

Bump `VERSION`, push to `main`. The workflow runs `swift test`, builds
`build/Foundry.app`, signs it with the Developer ID cert (hardened runtime +
timestamp), packages `Foundry-<version>-build-<run>.dmg`, notarizes the DMG and
staples its ticket, and updates the `v<version>` release in place with the DMG
and zip assets, so `releases/latest` is never empty. The release body is
`docs/release-notes/<version>.md` when that file exists. The zip holds the app
without a stapled ticket.

## Local build (same pipeline, your keychain)

```sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/verify-packaging.sh
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" BUILD_NUMBER=1 ./scripts/package-dmg.sh
NOTARY_PROFILE=mymac ./scripts/notarize-dmg.sh build/Foundry-*-build-1.dmg
```

Store notary credentials once for local use:

```sh
xcrun notarytool store-credentials mymac --apple-id you@example.com --team-id TEAMID
```

(it prompts for the app-specific password and saves it to the keychain).
