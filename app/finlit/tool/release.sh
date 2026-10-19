#!/usr/bin/env bash
# Local release build: universal APK + AAB (optionally the arm64-v8a APK), signed with the team key, checked.
#
#   FINNI_KEY_PROPERTIES=<path to key.properties outside the repo> tool/release.sh [--aab-only] [--arm64]
#
#   --aab-only   build only the AAB (after tools/stage_release.sh has built the APKs that go to /eksperty/)
#   --arm64      also build the arm64-v8a APK (versionCode 2000 + N: a separate file, never finni.apk)
#
# What goes to the three links is staged by tools/stage_release.sh, not by this script: builds are not
# byte-reproducible, so an APK from here has other sha256 than the one in stage/<sha>/. This script is for
# the AAB (TZ 3.3 "additionally"), RuStore drafts and standalone checks.
#
# Steps: key in (removed on exit, also on failure / Ctrl+C) -> clean tree -> pub get -> builds with
# --dart-define=BUILD_SHA=<7 hex> (the "Сборка ..." line in Settings) -> tool/check_manifest.sh (package,
# minSdk 26, not debuggable, team signature, versionCode >= 4) -> tool/check_size.sh -> SHA256SUMS ->
# tree still clean (pubspec.lock untouched).
# Output: $FINNI_RELEASE_OUT (default app/finlit/build/release/<sha7>/, gitignored):
#   finni-<sha7>-universal.apk, finni-<sha7>.aab, [finni-<sha7>-arm64-v8a.apk], SHA256SUMS
# The key is never printed; key.properties stays out of git (android/.gitignore).
set -euo pipefail

AAB_ONLY=0; ARM64=0
for a in "$@"; do
  case "$a" in
    --aab-only) AAB_ONLY=1 ;;
    --arm64) ARM64=1 ;;
    *) echo "usage: tool/release.sh [--aab-only] [--arm64]" >&2; exit 2 ;;
  esac
done

die() { echo "RELEASE FAILED: $*" >&2; exit 1; }
# a relative key path is meant from the caller's cwd: resolve it before cd
case "${FINNI_KEY_PROPERTIES:-}" in ""|/*|[A-Za-z]:*) ;; *) FINNI_KEY_PROPERTIES="$PWD/$FINNI_KEY_PROPERTIES" ;; esac
APP=$(cd "$(dirname "$0")/.." && pwd)
TOOL="$APP/tool"
cd "$APP"
[ -f pubspec.yaml ] && [ -d android ] || die "not a Flutter app dir: $APP"

export MSYS_NO_PATHCONV=1   # Git Bash would rewrite /-arguments for flutter.bat
export JAVA_HOME="${JAVA_HOME:-C:/Program Files/Android/Android Studio/jbr}"
upath() { cygpath -u "$1" 2>/dev/null || echo "$1"; }
export PATH="$(upath "$JAVA_HOME")/bin:$PATH"
# Flutter: from PATH, or FLUTTER_BIN=<flutter/bin dir> (no machine-specific default).
if ! command -v flutter >/dev/null 2>&1 && [ -n "${FLUTTER_BIN:-}" ]; then
  [ -d "$FLUTTER_BIN" ] || die "FLUTTER_BIN is not a directory: $FLUTTER_BIN"
  export PATH="$(upath "$FLUTTER_BIN"):$PATH"
fi
command -v flutter >/dev/null 2>&1 || die "flutter not on PATH; put it on PATH or set FLUTTER_BIN=<path to flutter/bin>"

# Key first: without it Gradle silently signs release with the debug key.
KEYP=android/key.properties
if [ ! -f "$KEYP" ]; then
  [ -n "${FINNI_KEY_PROPERTIES:-}" ] && [ -f "$FINNI_KEY_PROPERTIES" ] \
    || die "no release key: $APP/$KEYP missing and FINNI_KEY_PROPERTIES not set"
  trap 'rm -f "$APP/$KEYP"' EXIT
  trap 'exit 130' INT TERM
  trap 'exit 129' HUP
  cp "$FINNI_KEY_PROPERTIES" "$KEYP"
fi
git check-ignore -q "$KEYP" || die "$KEYP is not gitignored here: refusing to put a key into a tracked path"

[ -z "$(git status --porcelain)" ] || die "working tree is not clean"
SHA=$(git rev-parse HEAD)
S7=${SHA:0:7}
OUT="${FINNI_RELEASE_OUT:-$APP/build/release/$S7}"
VERSION=$(sed -n 's/^version: *//p' pubspec.yaml)
echo "== release $S7  version $VERSION  -> $OUT"
flutter --version 2>&1 | head -1

DEFINE="--dart-define=BUILD_SHA=$S7"
KOTLIN="--android-project-arg kotlin.incremental=false"   # incremental Kotlin cache breaks across drives E:/C:
flutter pub get
# Stale generated registrant can reference dev-only plugins in release (docs/sborka-i-dostavka.md, "Грабли").
rm -f android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java

mkdir -p "$OUT"
FILES=()
if [ $AAB_ONLY -eq 0 ]; then
  flutter build apk --release $KOTLIN "$DEFINE" || die "universal APK build failed"
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/finni-$S7-universal.apk"
  FILES+=("$OUT/finni-$S7-universal.apk")
  if [ $ARM64 -eq 1 ]; then
    flutter build apk --release --split-per-abi --target-platform android-arm64 $KOTLIN "$DEFINE" \
      || die "arm64 APK build failed"
    cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$OUT/finni-$S7-arm64-v8a.apk"
    FILES+=("$OUT/finni-$S7-arm64-v8a.apk")
  fi
fi
flutter build appbundle --release $KOTLIN "$DEFINE" || die "AAB build failed"
cp build/app/outputs/bundle/release/app-release.aab "$OUT/finni-$S7.aab"
FILES+=("$OUT/finni-$S7.aab")

bash "$TOOL/check_manifest.sh" "${FILES[@]}" || die "manifest check failed"
bash "$TOOL/check_size.sh" "${FILES[@]}" || die "size check failed"
( cd "$OUT" && sha256sum $(for f in "${FILES[@]}"; do basename "$f"; done) > SHA256SUMS )
[ -z "$(git status --porcelain)" ] || die "the build changed tracked files (pubspec.lock?): $(git status --porcelain | head -3)"

echo "RELEASE OK: $OUT"
cat "$OUT/SHA256SUMS"
