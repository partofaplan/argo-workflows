#!/usr/bin/env bash
# Deploys the scheduled file transfer demo to the cluster.
#   ./setup.sh            uses the "picard" kube context
#   CONTEXT=foo ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"
CONTEXT=${CONTEXT:-picard}
kc() { kubectl --context "$CONTEXT" "$@"; }
KEYS=.keys

# 1. SSH keys: one client key, plus a fixed host key per server so the
#    workflow can verify server identity through known_hosts.
mkdir -p "$KEYS"
for k in client source-host destination-host; do
  [[ -f $KEYS/$k ]] || ssh-keygen -q -t ed25519 -N '' -C "argo-demo-$k" -f "$KEYS/$k"
done
{
  echo "sftp-source.file-servers.svc.cluster.local $(cut -d' ' -f1,2 "$KEYS/source-host.pub")"
  echo "sftp-destination.file-servers.svc.cluster.local $(cut -d' ' -f1,2 "$KEYS/destination-host.pub")"
} > "$KEYS/known_hosts"

apply_secret() { kc create secret generic --dry-run=client -o yaml "$@" | kc apply -f -; }

# 2. The servers and their secrets
kc create namespace file-servers --dry-run=client -o yaml | kc apply -f -
apply_secret -n file-servers sftp-authorized-key --from-file=client.pub="$KEYS/client.pub"
apply_secret -n file-servers sftp-source-host-key --from-file=ssh_host_ed25519_key="$KEYS/source-host"
apply_secret -n file-servers sftp-destination-host-key --from-file=ssh_host_ed25519_key="$KEYS/destination-host"
kc apply -f 00-file-servers.yaml
kc -n file-servers rollout status deploy/sftp-source deploy/sftp-destination --timeout=180s

# 3. The workflow side: client credentials, template, schedule
apply_secret -n argo sftp-client-credentials \
  --from-file=id_ed25519="$KEYS/client" --from-file=known_hosts="$KEYS/known_hosts"
kc apply -f 10-workflow-template.yaml -f 20-cron-workflow.yaml

echo
echo "Done. The CronWorkflow runs every 5 minutes. To run it now:"
echo "  ./run-now.sh"
echo "To see files on both servers:"
echo "  ./peek.sh"
