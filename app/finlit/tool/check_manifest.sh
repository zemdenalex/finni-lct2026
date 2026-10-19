#!/usr/bin/env bash
# Release checks of a built APK / AAB: what the jury and RuStore get, read from the file itself.
#
#   tool/check_manifest.sh FILE.apk|FILE.aab [...]
#
# APK (aapt2 dump badging / xmltree, apksigner):
#   - package ru.lct2026.finlit, minSdk 26 (Android 8.0, TZ 3.1.1), versionCode >= FINNI_MIN_VERSION_CODE
#     (default 2: the build handed in on 29.09 has versionCode 1, a new build must install as an update);
#   - not debuggable: no application-debuggable in badging, 0 "debuggable" in the binary manifest
#     (control: the same dump must show minSdkVersion, so an empty dump cannot pass);
#   - no permissions except androidx's internal DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION (offline app, TZ 3.1);
#   - every signer is the team certificate (SHA-256 pin) and not this machine's debug key.
# AAB (manifest is protobuf, aapt2/apkanalyzer cannot read it):
#   - package string present, no "debuggable" attribute (control: minSdkVersion present);
#   - jarsigner verifies, every signer certificate is the team pin and not the debug key.
#   versionCode / permissions of the AAB are not read here (same Gradle config as the APK).
#
# Output: "MANIFEST OK: <file> ..." per file; on the first failure "MANIFEST FAILED: <reason>", exit 1.
# Env (optional): FINNI_CERT_SHA256, FINNI_MIN_VERSION_CODE, ANDROID_SDK_ROOT (or ANDROID_HOME; default $LOCALAPPDATA/Android/Sdk), JAVA_HOME.
set -euo pipefail

PACKAGE=ru.lct2026.finlit
MIN_SDK=26
MIN_VC="${FINNI_MIN_VERSION_CODE:-3}"
CERT_SHA256="${FINNI_CERT_SHA256:-099fdbcde3427509fb1817dcebbd3925b5bee55045e4a3dfe9df422d529c2c6b}"
ALLOWED_PERMS="$PACKAGE.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-${LOCALAPPDATA:+$LOCALAPPDATA/Android/Sdk}}}"
export JAVA_HOME="${JAVA_HOME:-C:/Program Files/Android/Android Studio/jbr}"
export PATH="$(cygpath -u "$JAVA_HOME" 2>/dev/null || echo "$JAVA_HOME")/bin:$PATH"

die() { echo "MANIFEST FAILED: $*" >&2; exit 1; }
[ $# -gt 0 ] || die "usage: check_manifest.sh FILE.apk|FILE.aab [...]"

bt_tool() {  # $1 tool name in the newest build-tools
  local bt; bt=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sort -V | tail -1)
  [ -n "$SDK" ] || die "Android SDK not found: set ANDROID_SDK_ROOT (or ANDROID_HOME) to the SDK dir"
  [ -n "$bt" ] || die "Android SDK build-tools not found under $SDK"
  local t; for t in "$bt$1.exe" "$bt$1.bat" "$bt$1"; do [ -f "$t" ] && { echo "$t"; return; }; done
  die "$1 not found in $bt"
}
AAPT2=$(bt_tool aapt2)
APKSIGNER=$(bt_tool apksigner)

# SHA-256 of this machine's debug certificate (the key Gradle falls back to without key.properties).
DEBUG_SHA256=""
if [ -f "$HOME/.android/debug.keystore" ] && command -v keytool >/dev/null 2>&1; then
  # keytool is a Windows binary: with MSYS_NO_PATHCONV=1 (exported by release.sh) it needs a native path.
  DEBUG_KS="$HOME/.android/debug.keystore"
  if command -v cygpath >/dev/null 2>&1; then DEBUG_KS=$(cygpath -w "$DEBUG_KS"); fi
  DEBUG_SHA256=$(keytool -list -v -keystore "$DEBUG_KS" -alias androiddebugkey \
    -storepass android 2>/dev/null | tr -d '\r' | awk '/SHA256:/ {print $2; exit}' | tr -d ':' | tr 'A-F' 'a-f')
fi

check_cert_list() {  # $1 file, $2 newline-separated lowercase hex SHA-256 of every signer
  local f="$1" list="$2" n bad
  n=$(printf '%s\n' "$list" | grep -c '^[0-9a-f]\{64\}$' || true)
  [ "$n" -gt 0 ] || die "$f: no signer certificate found"
  bad=$(printf '%s\n' "$list" | grep -v "^$CERT_SHA256\$" | head -1 || true)
  [ -z "$bad" ] || die "$f: signer $bad is not the team key $CERT_SHA256"
  if [ -n "$DEBUG_SHA256" ] && printf '%s\n' "$list" | grep -q "^$DEBUG_SHA256\$"; then
    die "$f: signed with the debug key ($DEBUG_SHA256)"
  fi
}

check_apk() {
  local f="$1" badging xml pkg vc vn minsdk tsdk perms p certs
  badging=$("$AAPT2" dump badging "$f" 2>&1 | tr -d '\r') || die "$f: aapt2 dump badging failed"
  pkg=$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging")
  vc=$(sed -n "s/^package: .* versionCode='\([0-9]*\)'.*/\1/p" <<<"$badging")
  vn=$(sed -n "s/^package: .* versionName='\([^']*\)'.*/\1/p" <<<"$badging")
  minsdk=$(sed -n "s/^minSdkVersion:'\([0-9]*\)'/\1/p" <<<"$badging")
  tsdk=$(sed -n "s/^targetSdkVersion:'\([0-9]*\)'/\1/p" <<<"$badging")
  [ "$pkg" = "$PACKAGE" ] || die "$f: package is '$pkg', not $PACKAGE"
  [ "$minsdk" = "$MIN_SDK" ] || die "$f: minSdk is '$minsdk', not $MIN_SDK (Android 8.0)"
  [[ "$vc" =~ ^[0-9]+$ ]] && [ "$vc" -ge "$MIN_VC" ] \
    || die "$f: versionCode '$vc' < $MIN_VC (must be above the 29.09 build, versionCode 1, to install as its update)"
  ! grep -q '^application-debuggable' <<<"$badging" || die "$f: application-debuggable in badging"
  xml=$("$AAPT2" dump xmltree --file AndroidManifest.xml "$f" 2>&1 | tr -d '\r') || die "$f: aapt2 dump xmltree failed"
  [ "$(grep -c 'minSdkVersion' <<<"$xml" || true)" -ge 1 ] || die "$f: manifest dump has no minSdkVersion (dump broken?)"
  [ "$(grep -ci 'debuggable' <<<"$xml" || true)" = 0 ] || die "$f: manifest has a debuggable attribute"
  perms=$(sed -n "s/^uses-permission[a-z0-9-]*: name='\([^']*\)'.*/\1/p" <<<"$badging")
  for p in $perms; do
    [[ " $ALLOWED_PERMS " == *" $p "* ]] || die "$f: unexpected permission $p"
  done
  certs=$("$APKSIGNER" verify --print-certs "$f" 2>&1 | tr -d '\r') || die "$f: apksigner verify failed"
  check_cert_list "$f" "$(sed -n 's/.*certificate SHA-256 digest: \([0-9a-f]\{64\}\)$/\1/p' <<<"$certs")"
  echo "MANIFEST OK: $f  package=$pkg versionCode=$vc versionName=$vn minSdk=$minsdk targetSdk=$tsdk perms=${perms:-none} cert=${CERT_SHA256:0:16}"
}

check_aab() {
  local f="$1" man cnt certs
  man=$(unzip -p "$f" base/manifest/AndroidManifest.xml 2>/dev/null | tr -c '[:print:]' '\n') \
    || die "$f: no base/manifest/AndroidManifest.xml"
  [ "$(grep -c 'minSdkVersion' <<<"$man" || true)" -ge 1 ] || die "$f: manifest has no minSdkVersion (not an AAB?)"
  cnt=$(grep -cF "$PACKAGE" <<<"$man" || true)
  [ "$cnt" -ge 1 ] || die "$f: package $PACKAGE not in manifest"
  [ "$(grep -ci 'debuggable' <<<"$man" || true)" = 0 ] || die "$f: manifest has a debuggable attribute"
  jarsigner -verify "$f" 2>&1 | tr -d '\r' | grep -q '^jar verified\.' || die "$f: jarsigner -verify failed"
  certs=$(keytool -printcert -jarfile "$f" 2>&1 | tr -d '\r') || die "$f: keytool -printcert failed"
  check_cert_list "$f" "$(awk '/SHA256:/ {print $2}' <<<"$certs" | tr -d ':' | tr 'A-F' 'a-f')"
  echo "MANIFEST OK: $f  package=$PACKAGE (aab) cert=${CERT_SHA256:0:16}"
}

for f in "$@"; do
  [ -f "$f" ] || die "no such file: $f"
  case "$f" in
    *.apk) check_apk "$f" ;;
    *.aab) check_aab "$f" ;;
    *) die "$f: expected .apk or .aab" ;;
  esac
done
