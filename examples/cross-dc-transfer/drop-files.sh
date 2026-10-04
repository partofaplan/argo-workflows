#!/usr/bin/env bash
# Drops N gibberish .txt files (default 50) into hercules' landing zone.
# The watcher notices them and, after 10 quiet seconds, triggers the transfer.
#   ./drop-files.sh        50 files
#   ./drop-files.sh 5      5 files
set -euo pipefail
SOURCE_CONTEXT=${SOURCE_CONTEXT:-k3d-hercules}
COUNT=${1:-50}

kubectl --context "$SOURCE_CONTEXT" -n landing-zone exec deploy/landing-zone -c watcher -- bash -c '
  set -euo pipefail
  cd /data/outbound
  stamp=$(date +%Y%m%d-%H%M%S)
  for i in $(seq -w 1 "$1"); do
    name="dataset-$stamp-$i.txt"
    # ~1-28 KB of random lowercase "words" (tr keeps ~1 in 10 random bytes);
    # write to a dot-file, then rename, so nothing ever sees a half-written file
    head -c $(( (RANDOM % 380 + 20) * 720 )) /dev/urandom | tr -dc "a-z " | fold -w 72 > ".$name.tmp"
    mv ".$name.tmp" "$name"
  done
  echo "Dropped $1 file(s) into hercules:/data/outbound ($(ls | wc -l) waiting)"
' _ "$COUNT"
