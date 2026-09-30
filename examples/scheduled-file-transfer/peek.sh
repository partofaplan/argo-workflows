#!/usr/bin/env bash
# Shows the files currently on each server.
set -euo pipefail
CONTEXT=${CONTEXT:-picard}

show() {  # show DEPLOYMENT DIR
  printf '\n== %s:%s ==\n' "$1" "$2"
  kubectl --context "$CONTEXT" -n file-servers exec "deploy/$1" -c sftp -- \
    sh -c 'cd "$1" && ls -1 | sed "s/^/  /"; echo "  ($(ls -1 | wc -l) files)"' _ "/home/demo/$2"
}

show sftp-source data/outbound
show sftp-source data/archive
show sftp-destination data/inbound
