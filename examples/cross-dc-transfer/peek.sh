#!/usr/bin/env bash
# Shows how many files are in each landing-zone directory, plus a few names.
set -euo pipefail
SOURCE_CONTEXT=${SOURCE_CONTEXT:-k3d-hercules}
DEST_CONTEXT=${DEST_CONTEXT:-k3d-xena}

show() {  # show CONTEXT LABEL DIR
  kubectl --context "$1" -n landing-zone exec deploy/landing-zone -c sshd -- sh -c '
    cd "/data/$2"
    printf "%-22s %4s files\n" "$1:$2" "$(ls -1 | wc -l)"
    ls -1 | head -3 | sed "s/^/    /"
    [ "$(ls -1 | wc -l)" -le 3 ] || echo "    ..."
  ' _ "$2" "$3"
}

show "$SOURCE_CONTEXT" hercules outbound
show "$SOURCE_CONTEXT" hercules sent
show "$DEST_CONTEXT" xena encrypted
show "$DEST_CONTEXT" xena inbound
