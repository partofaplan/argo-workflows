#!/usr/bin/env bash
# Deploys the cross-data-center transfer demo to two clusters:
#   SOURCE_CONTEXT (default k3d-hercules)  landing zone + watcher
#   DEST_CONTEXT   (default k3d-xena)      landing zone, Argo workflow, trigger
# Expects Argo Workflows and Argo Events to already be installed in the destination.
set -euo pipefail
cd "$(dirname "$0")"
SOURCE_CONTEXT=${SOURCE_CONTEXT:-k3d-hercules}
DEST_CONTEXT=${DEST_CONTEXT:-k3d-xena}
IMAGE=dc-transfer/tools:1.1
KEYS=.keys
src() { kubectl --context "$SOURCE_CONTEXT" "$@"; }
dst() { kubectl --context "$DEST_CONTEXT" "$@"; }
apply_secret() {  # apply_secret CONTEXT ARGS...
  local ctx=$1; shift
  kubectl --context "$ctx" create secret generic --dry-run=client -o yaml "$@" | kubectl --context "$ctx" apply -f -
}

# 1. Build the shared image and load it into both clusters (no registry needed)
docker build -q -t "$IMAGE" image/ >/dev/null
for ctx in "$SOURCE_CONTEXT" "$DEST_CONTEXT"; do
  k3d image import -c "${ctx#k3d-}" "$IMAGE" >/dev/null
done

# 2. Keys, kept in .keys/ (gitignored) so reruns don't rotate them
#    - one SSH client key for the workflow, and a fixed host key per landing
#      zone so the workflow can verify which server it's talking to
#    - xena's age key pair: hercules only ever sees the public half
#    - a bearer token for the webhook
mkdir -p "$KEYS"
for k in client hercules-host xena-host; do
  [[ -f $KEYS/$k ]] || ssh-keygen -q -t ed25519 -N '' -C "cross-dc-$k" -f "$KEYS/$k"
done
[[ -s $KEYS/xena-age-identity ]] || docker run --rm "$IMAGE" age-keygen 2>/dev/null > "$KEYS/xena-age-identity"
grep -o 'age1[0-9a-z]*' "$KEYS/xena-age-identity" | head -1 > "$KEYS/xena-age-recipient"
[[ -s $KEYS/webhook-token ]] || od -An -tx1 -N24 /dev/urandom | tr -d ' \n' > "$KEYS/webhook-token"
{
  echo "[host.k3d.internal]:2322 $(cut -d' ' -f1,2 "$KEYS/hercules-host.pub")"
  echo "landing-zone.landing-zone.svc.cluster.local $(cut -d' ' -f1,2 "$KEYS/xena-host.pub")"
} > "$KEYS/known_hosts"

# 3. Source landing zone (hercules)
src create namespace landing-zone --dry-run=client -o yaml | src apply -f -
apply_secret "$SOURCE_CONTEXT" -n landing-zone landing-zone-host-key --from-file=ssh_host_ed25519_key="$KEYS/hercules-host"
apply_secret "$SOURCE_CONTEXT" -n landing-zone landing-zone-authorized-key --from-file=client.pub="$KEYS/client.pub"
apply_secret "$SOURCE_CONTEXT" -n landing-zone landing-zone-webhook --from-file=token="$KEYS/webhook-token"
src apply -f 00-landing-zone-hercules.yaml

# 4. Destination landing zone (xena)
dst create namespace landing-zone --dry-run=client -o yaml | dst apply -f -
apply_secret "$DEST_CONTEXT" -n landing-zone landing-zone-host-key --from-file=ssh_host_ed25519_key="$KEYS/xena-host"
apply_secret "$DEST_CONTEXT" -n landing-zone landing-zone-authorized-key --from-file=client.pub="$KEYS/client.pub"
dst apply -f 01-landing-zone-xena.yaml

# 5. Workflow + trigger (xena)
apply_secret "$DEST_CONTEXT" -n argo cross-dc-transfer-credentials \
  --from-file=id_ed25519="$KEYS/client" --from-file=known_hosts="$KEYS/known_hosts" \
  --from-file=age-recipient="$KEYS/xena-age-recipient"
apply_secret "$DEST_CONTEXT" -n argo xena-age-identity --from-file=identity="$KEYS/xena-age-identity"
apply_secret "$DEST_CONTEXT" -n argo landing-zone-webhook --from-file=token="$KEYS/webhook-token"
dst apply -f 10-workflow-template.yaml -f 20-events-xena.yaml

# 6. Email notifications: a Mailpit test inbox, and SMTP settings pointing at it.
#    The Secret is only created if missing, so real SMTP settings you put in it
#    later survive reruns (see README, "Email notifications").
dst apply -f 30-mailpit-xena.yaml
if ! dst -n argo get secret cross-dc-transfer-smtp >/dev/null 2>&1; then
  dst -n argo create secret generic cross-dc-transfer-smtp \
    --from-literal=host=mailpit.mail.svc.cluster.local --from-literal=port=1025 \
    --from-literal=from=argo@xena.internal --from-literal=to=data-ops@xena.internal
fi

# 7. Wait for everything to come up
src -n landing-zone rollout status deploy/landing-zone --timeout=180s
dst -n landing-zone rollout status deploy/landing-zone --timeout=180s
dst -n mail rollout status deploy/mailpit --timeout=180s
for kind in eventsource sensor; do
  until dst -n argo get pods -l "$kind-name" -o name 2>/dev/null | grep -q .; do sleep 2; done
done
dst -n argo wait pod -l eventsource-name=landing-zone --for=condition=Ready --timeout=180s >/dev/null
dst -n argo wait pod -l sensor-name=cross-dc-transfer --for=condition=Ready --timeout=180s >/dev/null

echo
echo "Done. Drop files on hercules to trigger a transfer:"
echo "  ./drop-files.sh        # 50 files"
echo "  ./peek.sh              # see both landing zones"
echo "Failed runs and conflicts are emailed to the Mailpit inbox: https://mail.tail18466c.ts.net"
