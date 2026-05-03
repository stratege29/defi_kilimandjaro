---
name: release-build
description: Build release iOS (.ipa) and Android (.aab) artifacts for submission to App Store and Play Store. Bumps version, runs tests, builds with obfuscation, validates size, and outputs to artifacts/.
disable-model-invocation: true
---

# Release Build

Build release artifacts for submission. Args: $ARGUMENTS (e.g. "1.0.0" or "patch"/"minor"/"major")

## Steps

1. **Determine version**:
   - If arg is `patch`/`minor`/`major`, bump from current `pubspec.yaml`
   - If arg is `X.Y.Z`, use it directly
   - Update `pubspec.yaml` version line: `version: X.Y.Z+<build_number>`
   - Increment `build_number` automatically

2. **Pre-flight checks** (abort if any fail):
   - `git status` clean
   - Branch is `main`
   - `flutter analyze` zero issues
   - `flutter test` all green (coverage report)
   - `flutter test integration_test/` golden path passes

3. **Build iOS**:
   ```bash
   flutter build ipa \
     --release \
     --obfuscate \
     --split-debug-info=build/debug-info \
     --dart-define=FIREBASE_PROJECT=kilimandjaro-prod
   ```
   Output: `build/ios/ipa/*.ipa`

4. **Build Android**:
   ```bash
   flutter build appbundle \
     --release \
     --obfuscate \
     --split-debug-info=build/debug-info \
     --dart-define=FIREBASE_PROJECT=kilimandjaro-prod
   ```
   Output: `build/app/outputs/bundle/release/app-release.aab`

5. **Validate size**:
   - iOS .ipa < 60 MB
   - Android .aab < 30 MB
   - Abort and report if exceeded

6. **Move to artifacts/**:
   ```bash
   mkdir -p artifacts/v<version>
   mv build/ios/ipa/*.ipa artifacts/v<version>/
   cp build/app/outputs/bundle/release/app-release.aab artifacts/v<version>/
   cp -r build/debug-info artifacts/v<version>/
   ```

7. **Tag git**:
   ```bash
   git tag -a v<version> -m "Release v<version>"
   ```
   Don't push automatically; user pushes when ready.

8. **Generate release notes**:
   - From `git log <previous-tag>..HEAD --oneline`
   - Save to `artifacts/v<version>/RELEASE_NOTES.md`
   - Categorize: Features / Fixes / Performance

9. **Report**:
   - Version + build number
   - File paths and sizes
   - Crash-free baseline (last 1000 sessions from Crashlytics if available)
   - Next steps: upload to TestFlight + Play Console internal track

## Constraints

- NEVER ship a release that fails analyze or test
- NEVER strip `--obfuscate` from release builds
- ALWAYS preserve `debug-info` (needed for Crashlytics symbolication)
- NEVER push tags automatically (user controls release moment)
- If version already exists as tag, abort with clear error
