#!/usr/bin/env bash
# Removes everything setup.sh created (keys in .keys/ are kept).
set -euo pipefail
SOURCE_CONTEXT=${SOURCE_CONTEXT:-k3d-hercules}
DEST_CONTEXT=${DEST_CONTEXT:-k3d-xena}
dst() { kubectl --context "$DEST_CONTEXT" "$@"; }

dst -n argo delete sensor cross-dc-transfer --ignore-not-found
dst -n argo delete eventsource landing-zone --ignore-not-found
dst -n argo delete eventbus default --ignore-not-found
dst -n argo delete ingress landing-zone-webhook --ignore-not-found
dst -n argo delete rolebinding,role,serviceaccount cross-dc-transfer-sensor --ignore-not-found
dst -n argo delete workflow -l app=cross-dc-transfer --ignore-not-found
dst -n argo delete workflowtemplate cross-dc-transfer --ignore-not-found
dst -n argo delete secret cross-dc-transfer-credentials xena-age-identity landing-zone-webhook --ignore-not-found
dst delete namespace landing-zone --ignore-not-found
kubectl --context "$SOURCE_CONTEXT" delete namespace landing-zone --ignore-not-found
