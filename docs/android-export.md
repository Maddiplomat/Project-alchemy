# Android Export

This project is configured for a phone-first Android MVP in landscape orientation.

## Preset Summary

- Export preset: `Android`
- Output: `build/android/project-alchemy-debug.apk`
- App name: `Project Alchemy`
- Package name: `com.angrydiplomat.projectalchemy`
- Version code: `1`
- Version name: `0.1.0`
- Orientation: landscape
- Architectures: `arm64-v8a` only
- Tablet support: intentionally deferred until the phone layout is fully playable

## Local Requirements

Godot 4.7 Android export depends on four local pieces:

1. A full JDK, not only the macOS Java shim.
2. Android SDK, including platform tools and build tools.
3. Android export templates for Godot 4.7.
4. A project-local debug keystore for internal APK signing.

The local Godot editor settings currently point at:

- Java SDK: configured in `Editor Settings > Export > Android > Java SDK Path`
- Android SDK: `/Users/angrydiplomat/Library/Android/sdk`
- Debug keystore default: `/Users/angrydiplomat/Library/Application Support/Godot/keystores/debug.keystore`

If those paths change, update your local Godot editor export settings before exporting.

## Current Machine Gaps

On the audited macOS machine, Android export is blocked because:

- there is no working Java runtime or compiler available from the shell
- `export/android/java_sdk_path` is empty in `editor_settings-4.7.tres`
- `/Users/angrydiplomat/Library/Android/sdk` does not currently exist
- `build/android/keystores/project-alchemy-debug.keystore` does not currently exist
- `~/Library/Application Support/Godot/export_templates/4.7.stable` does not currently exist

Treat those as required setup tasks before attempting export verification.

## Recommended Setup Order

1. Install a full JDK.
2. Set `JAVA_HOME` and verify `java`, `javac`, and `keytool` all work from the shell.
3. Set `Editor Settings > Export > Android > Java SDK Path` to that JDK home.
4. Install the Android SDK and point Godot at the real SDK directory.
5. Install Godot 4.7 Android export templates.
6. Generate `build/android/keystores/project-alchemy-debug.keystore`.
7. Re-run the environment verifier before exporting.

## JDK Notes

If using Homebrew OpenJDK, install a real JDK package first. After installation, Godot should point to the JDK home directory, and the shell should satisfy:

```bash
java -version
javac -version
keytool -help
```

If macOS still resolves `/usr/bin/java` to the stub launcher, either export `JAVA_HOME` and prepend `"$JAVA_HOME/bin"` to `PATH`, or use the Homebrew-provided JDK path directly in Godot's Android export settings.

## Debug Signing

Internal debug exports use the project-local keystore:

- `build/android/keystores/project-alchemy-debug.keystore`
- Alias: `androiddebugkey`
- Password: `android`

Generate it after installing a JDK:

```bash
keytool -genkeypair -v \
  -keystore build/android/keystores/project-alchemy-debug.keystore \
  -storepass android \
  -alias androiddebugkey \
  -keypass android \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=Project Alchemy Debug,O=Project Alchemy,C=US"
```

This key is for internal device testing only. Do not reuse it for public releases.

## Release Signing Plan

Do not commit the release keystore to the repository.

Recommended release flow:

1. Create a dedicated release keystore outside the repo, ideally in a secrets-managed location.
2. Use a unique alias such as `project-alchemy-release`.
3. Store the keystore path, alias, and passwords in CI or a secure team password vault.
4. Fill `keystore/release`, `keystore/release_user`, and `keystore/release_password` in a local uncommitted export preset override or CI-time patch step.
5. If publishing through Google Play, enable Play App Signing and archive the upload key separately from the app signing key.

## Export Exclusions

The Android preset excludes development-only content:

- `addons/godot_mcp/*`
- `scenes/dev/*`
- `scripts/dev/*`

`scripts/MCPRuntime.gd` is safe to keep because it only starts the editor MCP bridge when Godot is running with the `editor` feature.

## Export Steps

1. Open the project in Godot 4.7.
2. Confirm `Editor Settings > Export > Android` points at a valid SDK path.
3. Install Android export templates if the Android preset shows template errors.
4. Connect a test phone with USB debugging enabled.
5. Export with the `Android` preset to `build/android/project-alchemy-debug.apk`.
6. Install the APK on the device and launch it.

## Headless Environment Check

Run this helper from the project root:

```bash
zsh scripts/dev/verify_android_export_env.sh
```

It verifies:

- configured Java SDK path exists
- `java`, `javac`, and `keytool` work from the current environment
- Godot 4.7 editor settings are present
- configured Android SDK path exists
- project-local debug keystore exists
- Android export templates directory exists

## Device QA Checklist

Before calling Android support stable, verify on a physical phone:

1. App installs and launches without a keyboard or mouse.
2. Orientation stays locked to landscape during gameplay.
3. A new save persists after fully closing and reopening the app.
4. HUD, build mode, journal, and inventory remain usable on-device.
5. Exported APK does not bundle `addons/godot_mcp`.

To verify exported contents after building:

```bash
sh scripts/dev/verify_export_excludes_mcp.sh build/android/project-alchemy-debug.apk
```
