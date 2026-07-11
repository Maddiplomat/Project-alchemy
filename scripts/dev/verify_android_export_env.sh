#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EDITOR_SETTINGS="$HOME/Library/Application Support/Godot/editor_settings-4.7.tres"
DEBUG_KEYSTORE="$PROJECT_ROOT/build/android/keystores/project-alchemy-debug.keystore"
TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/4.7.stable"

JAVA_SDK_PATH="$(sed -n 's/^export\/android\/java_sdk_path = "\(.*\)"/\1/p' "$EDITOR_SETTINGS" 2>/dev/null)"
SDK_PATH="$(sed -n 's/^export\/android\/android_sdk_path = "\(.*\)"/\1/p' "$EDITOR_SETTINGS" 2>/dev/null)"

if [[ -z "${JAVA_HOME:-}" && -n "$JAVA_SDK_PATH" ]]; then
  export JAVA_HOME="$JAVA_SDK_PATH"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

if ! java -version >/dev/null 2>&1; then
  echo "missing: working Java runtime"
  echo "hint: install a full JDK and set Godot Editor Settings > Export > Android > Java SDK Path"
  exit 1
fi

if ! keytool -help >/dev/null 2>&1; then
  echo "missing: working keytool runtime (install a JDK, not only the macOS shim)"
  exit 1
fi

if ! javac -version >/dev/null 2>&1; then
  echo "missing: working javac compiler from a full JDK"
  exit 1
fi

if [[ ! -f "$EDITOR_SETTINGS" ]]; then
  echo "missing: $EDITOR_SETTINGS"
  exit 1
fi

if [[ -z "$JAVA_SDK_PATH" ]]; then
  echo "missing: Java SDK path in $EDITOR_SETTINGS"
  exit 1
fi

if [[ ! -d "$JAVA_SDK_PATH" ]]; then
  echo "missing: Java SDK directory $JAVA_SDK_PATH"
  exit 1
fi

if [[ -z "$SDK_PATH" ]]; then
  echo "missing: Android SDK path in $EDITOR_SETTINGS"
  exit 1
fi

if [[ ! -d "$SDK_PATH" ]]; then
  echo "missing: Android SDK directory $SDK_PATH"
  exit 1
fi

if [[ ! -d "$PROJECT_ROOT/build/android/keystores" ]]; then
  echo "missing: keystore directory $PROJECT_ROOT/build/android/keystores"
  exit 1
fi

if [[ ! -f "$DEBUG_KEYSTORE" ]]; then
  echo "missing: debug keystore $DEBUG_KEYSTORE"
  exit 1
fi

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "missing: Godot export templates directory $TEMPLATES_DIR"
  exit 1
fi

echo "ok: Java SDK found at $JAVA_SDK_PATH"
echo "ok: editor settings present"
echo "ok: Android SDK found at $SDK_PATH"
echo "ok: debug keystore found at $DEBUG_KEYSTORE"
echo "ok: export templates directory found at $TEMPLATES_DIR"
