#!/usr/bin/env bash
set -euo pipefail
# No shell tracing, credentials in argv, key.properties, cache or key artifacts.
for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required signing input: $name" >&2
    exit 1
  fi
done
python3 tool/android_release.py preflight
umask 077
signing_dir="$RUNNER_TEMP/tandemlog-signing"
mkdir "$signing_dir"
trap 'rm -rf -- "$signing_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export ANDROID_KEYSTORE_PATH="$signing_dir/release.keystore"
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > "$ANDROID_KEYSTORE_PATH"
unset ANDROID_KEYSTORE_BASE64
export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false"
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/tandemlog-android.apk
python3 tool/android_release.py dist/tandemlog-android.apk
(cd dist && sha256sum tandemlog-android.apk > android-SHA256SUMS.txt)
