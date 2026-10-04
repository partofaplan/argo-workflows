#!/usr/bin/env bash
# Re-drops files under names xena has already received, to show how repeats
# are handled. Picks names from hercules' sent/:
#   N exact copies              -> duplicates: skipped, not resent
#   N same names, new content   -> conflicts: set aside in hercules conflicts/
#   ./drop-repeats.sh       2 of each
#   ./drop-repeats.sh 5     5 of each
set -euo pipefail
SOURCE_CONTEXT=${SOURCE_CONTEXT:-k3d-hercules}
COUNT=${1:-2}

kubectl --context "$SOURCE_CONTEXT" -n landing-zone exec deploy/landing-zone -c watcher -- bash -c '
  set -euo pipefail
  cd /data
  mapfile -t names < <(ls -1 sent | grep -E "^[A-Za-z0-9._-]+\.txt$" | sort | head -n $(( $1 * 2 )))
  if (( ${#names[@]} < $1 * 2 )); then
    echo "Need at least $(( $1 * 2 )) files in sent/; run ./drop-files.sh first" >&2
    exit 1
  fi
  for f in "${names[@]:0:$1}"; do
    cp "sent/$f" "outbound/.$f.tmp" && mv "outbound/.$f.tmp" "outbound/$f"
    echo "duplicate  $f  (exact copy)"
  done
  for f in "${names[@]:$1}"; do
    echo "revised $(date -Is): $(head -c 3000 /dev/urandom | tr -dc "a-z ")" > "outbound/.$f.tmp"
    mv "outbound/.$f.tmp" "outbound/$f"
    echo "conflict   $f  (same name, new content)"
  done
' _ "$COUNT"
