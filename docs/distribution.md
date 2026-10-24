# Distribution and security

How Molt is signed, notarized and shipped, what it does to keep your data safe, and what still stands between Molt and the Mac App Store.

## Why testers see "Molt is damaged" or "can't be checked for malicious software"

macOS Gatekeeper only opens downloaded apps that are signed with a **Developer ID** certificate and **notarized** by Apple. A build signed ad-hoc or with "Molt Local Signing" is fine on the Mac that built it, but every other Mac blocks it as unverified. `./scripts/package.sh` now prints a warning whenever it makes a DMG like that.

## One-time setup (needs the paid Apple Developer Program)

1. Join the Apple Developer Program ($99 a year) at developer.apple.com/programs.
2. Create the certificate. In Xcode: Settings, Accounts, your team, Manage Certificates, +, **Developer ID Application**. Or create it at developer.apple.com/account/resources/certificates with a CSR from Keychain Access. It must end up in your login keychain with its private key. Check with:

   ```sh
   security find-identity -v -p codesigning   # shows "Developer ID Application: Your Name (TEAMID)"
   ```

3. Save notarization credentials once. Make an app-specific password at account.apple.com (Sign-In and Security, App-Specific Passwords), then:

   ```sh
   xcrun notarytool store-credentials molt-notary --apple-id you@example.com --team-id TEAMID
   ```

## Building a release DMG

```sh
MOLT_NOTARY_PROFILE=molt-notary ./scripts/package.sh 0.9.3
```

The script finds the Developer ID certificate by itself, then:

1. signs every nested binary and the app with the **hardened runtime** and a secure timestamp, giving only the app the entitlements in `scripts/Molt.entitlements`;
2. notarizes the app and staples the ticket to it, so it opens even offline after it's copied out of the DMG;
3. builds the DMG, signs it, notarizes it and staples it;
4. checks the result with `spctl`, the same check Gatekeeper runs on testers' Macs.

Set `MOLT_REQUIRE_NOTARIZATION=1` to make the script fail instead of producing a DMG that other Macs block. `MOLT_SIGN_IDENTITY` forces a particular certificate. `MOLT_BUILD` sets `CFBundleVersion` separately from the marketing version.

### GitHub releases

`.github/workflows/release.yml` notarizes tagged releases when these repository secrets exist (Settings, Secrets and variables, Actions):

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Your Developer ID certificate and private key exported from Keychain Access as .p12, then `base64 -i cert.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | The password you gave the .p12 export |
| `NOTARY_KEY_P8_BASE64` | An App Store Connect API key (Users and Access, Integrations, Team Keys, role Developer), `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_KEY_ID` | That key's ID |
| `NOTARY_ISSUER_ID` | The issuer ID shown above the keys list |

Once the certificate secret is set, a release that can't be notarized fails rather than publishing a blocked DMG. The certificate goes into a throwaway keychain that is deleted at the end of the job. Never commit `.p12`, `.p8` or `.cer` files; `.gitignore` excludes them.

## What protects your data

- **Code integrity.** The hardened runtime stops other processes from injecting code into Molt or attaching a debugger, and blocks loading libraries not signed by the same team. Molt takes no exceptions (no JIT, unsigned memory, DYLD variables or library validation exceptions).
- **Least privilege.** Molt's only entitlements are Apple Events, camera and calendars, and macOS still asks you before each one is used. Screen Recording, Accessibility, Bluetooth and Reminders also go through macOS permission prompts.
- **Secrets in the keychain.** Molt account, Spotify, GitHub and AI provider keys live in the login keychain, never in preferences or files. Settings export only includes layout and preference keys.
- **Claude Code's login** is read through the Security framework only while Claude usage is turned on. macOS asks you first, and "Always Allow" trusts only Molt's signature. The token is never stored and only sent to Anthropic.
- **Local files.** `~/Library/Application Support/Molt` is limited to your user account (mode 700). Clipboard history is excluded from Time Machine and skips items password managers mark as concealed or transient.
- **Local listeners** (agent hooks, Spotify sign-in) bind only to 127.0.0.1. Agent hooks need a random token (two UUIDs) compared in constant time. The Spotify callback checks a random `state` value.
- **Network.** App Transport Security is left at its defaults, so every remote connection is HTTPS. Plain HTTP is used only for services on this Mac (Ollama, LM Studio, the loopback listeners).
- **Downloads.** The local model and llama.cpp runtime are pinned and checked against SHA-256 hashes before use.
- **Server data.** Every Supabase table has row level security, and helper functions run as `security definer` with an empty `search_path`.
- **Privacy manifest.** `PrivacyInfo.xcprivacy` declares no tracking, only the email and user ID needed for Molt accounts, and the reasons for each "required reason" API Molt calls.

## Mac App Store readiness

Molt is not ready for the Mac App Store yet. The store requires the **App Sandbox**, and these features can't work inside it as written:

| Feature | Why the sandbox blocks it | Path forward |
| --- | --- | --- |
| Agents and Sessions (Claude Code / Codex hooks) | Reads and edits `~/.claude/settings.json` and `~/.codex/config.toml` | Ask the person to pick the folder once (security-scoped bookmark), or show the hook text to paste |
| Claude and Codex plan usage | Reads another app's keychain item and `~/.codex/sessions` | Drop from the App Store edition, or a folder bookmark for Codex |
| Quick actions: show/hide desktop, display sleep, keep awake, Shortcuts | Runs `defaults`, `killall Finder`, `pmset`, `caffeinate`, `shortcuts` | Use `IOPMAssertion` for keep awake; drop the rest |
| Lens permission reset | Runs `tccutil` | Drop; link to System Settings instead |
| Music and Finder control | Apple Events to System Events and Finder need temporary exception entitlements that App Review rarely approves | Keep Spotify/Music via `com.apple.security.scripting-targets`; drop System Events and Finder |
| Bluetooth toggle | Private IOBluetooth calls | Drop |
| Ollama start, git, system_profiler | Launches programs outside the app | Drop or ask Ollama to be running |
| Local model runtime | Child executables must be signed and inherit the sandbox | Sign with `com.apple.security.inherit` |
| Existing data | A sandboxed app sees a new container, not `~/Library/Application Support/Molt` | One-time import with a folder picker |

Other App Store requirements: an "Apple Distribution" and "3rd Party Mac Developer Installer" certificate, a provisioning profile embedded in the app, a `.pkg` built with `productbuild`, an incrementing `CFBundleVersion` (`MOLT_BUILD`), App Store Connect metadata including a privacy policy URL, and uploading with Xcode or Transporter. The Info.plist keys, privacy manifest and export compliance flag Apple checks are already in place.
