#!/usr/bin/env bash
# Removes everything setup.sh created (keys in .keys/ are kept).
set -euo pipefail
CONTEXT=${CONTEXT:-picard}
kc() { kubectl --context "$CONTEXT" "$@"; }
kc -n argo delete cronworkflow sftp-file-transfer --ignore-not-found
kc -n argo delete workflow -l app=file-transfer-demo --ignore-not-found
kc -n argo delete workflowtemplate sftp-file-transfer --ignore-not-found
kc -n argo delete secret sftp-client-credentials --ignore-not-found
kc delete namespace file-servers --ignore-not-found
