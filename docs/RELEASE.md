# Release

MarketFlow release engineering for Android (verified process, with the build
log appended by the orchestrator after the release builds run) and iOS
(honest status: scaffolded, **not verified** — building iOS requires macOS +
Xcode + Apple signing, and this project was built on Linux).

## Toolchain

| Component | Version used | Notes |
| --- | --- | --- |
| Flutter | 3.47.5 stable (Dart 3.13.4) | pinned in CI; local toolchain at `/home/z/flutter` |
| Java | Temurin JDK 17 | `javac` required (a JRE is not enough for Gradle) |
| Android SDK | platforms;android-36, build-tools;36.0.0 | licenses accepted, `flutter config --android-sdk` set |
| Android NDK | 28.2.13676358 | **required** by the plugin graph (`path_provider_android` → `jni` → CMake); install with sdkmanager before building, remove after if disk-constrained |

## Versioning

`pubspec.yaml` → `version: 1.0.0+1` — Flutter maps `1.0.0` to
`versionName` / `CFBundleShortVersionString` and `+1` to `versionCode` /
`CFBundleVersion`. Bump both for every Play Store upload
(`flutter build` also accepts `--build-name` / `--build-number`).

## Android — the universal 3-ABI APK (the REQUIRED artifact)

```bash
flutter build apk --release \
  --target-platform android-arm,android-arm64,android-x64
```

**This exact command is the contract.** Deliberately:

- **Universal, not arm64-only.** An arm64-only APK does not run on 32-bit
  armeabi-v7a devices still in the field; the universal artifact installs
  everywhere Android itself can.
- **Not `--split-per-abi`.** Split APKs are smaller *per device* but each
  fragment is a separate artifact with its own versionCode bump; they're a
  Play-Store-delivery optimization, not a shareable single file. The main
  artifact here must be one installable file for any reviewer/device.
  (Splits can be produced additionally if a store workflow wants them.)

Output: `build/app/outputs/flutter-apk/app-release.apk` (expect ~20 MB for
this app, based on the sibling project's equivalent build).

### Android App Bundle (for Play Store delivery)

```bash
flutter build appbundle --release \
  --target-platform android-arm,android-arm64,android-x64
```

Output: `build/app/outputs/bundle/release/app-release.aab`. Play processes
this into device-specific APKs automatically — same 3-ABI instruction.

### ABI verification (always run after a build)

Confirm the artifact actually contains all three ABIs:

```bash
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep lib/
# expect: lib/armeabi-v7a/libapp.so + libflutter.so
#         lib/arm64-v8a/libapp.so  + libflutter.so
#         lib/x86_64/libapp.so     + libflutter.so
```

(For an `.aab` the check is `bundletool dump manifest` / extracting with
`unzip -l` and inspecting `base/lib/…`.) A missing `lib/armeabi-v7a` entry
means the command above was not the universal one — do not ship that file.

## Signing reality

**In this repository/environment the release artifacts are debug-signed.**
There is no upload keystore (creating a real one requires
keytool + Play App Signing enrollment), so `flutter build --release` falls
back to `%USERPROFILE%/.android/debug.keystore` equivalents. That is fine
for distribution-as-a-portfolio-demo (installable on any device), and it is
**explicitly not** fine for Play Store upload. No keystore or password is —
or will ever be — committed (see `.gitignore` rules; secret scans pass).

Real Play Store signing setup (documented, not performed):

1. `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA
   -keysize 2048 -validity 10000 -alias upload`
2. `android/key.properties` (gitignored):

   ```properties
   storePassword=<password from step 1>
   keyPassword=<password from step 1>
   keyAlias=upload
   storeFile=/absolute/path/to/upload-keystore.jks
   ```

3. `android/app/build.gradle.kts` reads it and sets
   `signingConfig = signingConfigs.create("release")` (docs:
   flutter.dev deployment guide). Then enroll the upload key in Play App
   Signing; Google re-signs with the app signing key and keeps the upload
   key revocable.

## Pre-release gates

Run in this order (all green before building):

```bash
dart format --output=none --set-exit-if-changed .   # 0 changed
flutter analyze                                     # No issues found!
flutter test                                        # 215/215
```

Plus a secrets scan of the tree (keystore, tokens, passwords) and a
re-read of README/docs claims against reality.

## Build verification log

> The orchestrator appends actual command outputs here after the release
> builds run. Until an entry exists below this line, **no build claim in
> this document is a verified claim** — the commands are the verified
> *process* (proven on the sibling CareRoute build), not yet executed
> artifacts of this repo.

*(no entries yet — build run pending)*

## iOS — scaffolded, NOT VERIFIED

The `ios/` runner is scaffolded by `flutter create` (bundle id
`com.sevenclan.marketflow`). What iOS release would require, and why it
was not done here:

- macOS + Xcode (this environment is Linux — `flutter build ipa` cannot
  run at all);
- an Apple Developer account, a distribution certificate and a provisioning
  profile (signing);
- `flutter build ipa --release` + App Store Connect upload via
  Transporter/`xcrun altool`, or ad-hoc `.ipa` for direct install.

Claims about iOS behavior in this codebase are therefore limited to: the
Dart/Flutter layer is platform-agnostic, `flutter_secure_storage` maps to
the iOS Keychain, and no iOS-specific plugins are used beyond the standard
runner set. No iOS device or simulator ever ran this app. Any CV or
interview claim must reflect that.

## Distribution notes (demo context)

- The in-process mock backend ships **in** the release build — the app is
  fully self-contained offline-of-any-server; no API keys or endpoints are
  embedded (there are none in the codebase at all).
- Release artifacts are expected to be debug-signed (above) — document that
  alongside any share link ("install via 'unknown sources'").
- Build outputs live under gitignored `build/`; preserve release artifacts
  outside the repo when needed.
