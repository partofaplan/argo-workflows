#!/usr/bin/env bash
# Starts a run immediately instead of waiting for the schedule.
# Extra args become template parameters, e.g.  ./run-now.sh chaos-percent=40
set -euo pipefail
CONTEXT=${CONTEXT:-picard}

params=""
for kv in "$@"; do
  params+="      - {name: \"${kv%%=*}\", value: \"${kv#*=}\"}"$'\n'
done

kubectl --context "$CONTEXT" -n argo create -o name -f - <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: sftp-file-transfer-manual-
  labels: {app: file-transfer-demo}
spec:
  workflowTemplateRef: {name: sftp-file-transfer}
${params:+  arguments:
    parameters:
$params}
YAML
