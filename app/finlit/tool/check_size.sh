#!/usr/bin/env bash
# Size of release files (APK / AAB): bytes, MB (10^6, as Flutter and our docs count) and MiB (as Android shows).
#
#   tool/check_size.sh FILE [...]
#
# The only hard limit we have in writing is RuStore's 5 GB per file (docs/sborka-i-dostavka.md, section 5);
# neither the TZ nor the release plan sets a size target (the APK size question is decision DEN-15,
# docs/final/razmer-apk.md in the team folder). So by default this script prints and fails only above 5000 MB.
# FINNI_MAX_MB=<n> sets a tighter ceiling for a run (e.g. FINNI_MAX_MB=120 to catch an art regression).
set -euo pipefail

MAX_MB="${FINNI_MAX_MB:-5000}"
die() { echo "SIZE FAILED: $*" >&2; exit 1; }
[ $# -gt 0 ] || die "usage: check_size.sh FILE [...]"
[[ "$MAX_MB" =~ ^[0-9]+$ ]] || die "FINNI_MAX_MB must be a whole number of MB, got '$MAX_MB'"

printf '%-48s %12s %9s %9s\n' file bytes MB MiB
rc=0
for f in "$@"; do
  [ -f "$f" ] || die "no such file: $f"
  b=$(stat -c %s "$f")
  printf '%-48s %12s %9s %9s\n' "$(basename "$f")" "$b" \
    "$(awk -v b="$b" 'BEGIN {printf "%.1f", b / 1e6}')" "$(awk -v b="$b" 'BEGIN {printf "%.1f", b / 1048576}')"
  if [ "$b" -gt $((MAX_MB * 1000000)) ]; then
    echo "SIZE FAILED: $(basename "$f") is above $MAX_MB MB" >&2
    rc=1
  fi
done
[ $rc -eq 0 ] && echo "SIZE OK: limit $MAX_MB MB"
exit $rc
