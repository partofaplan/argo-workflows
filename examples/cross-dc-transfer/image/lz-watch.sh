#!/bin/bash
# Watches the landing zone and tells xena when files have landed.
#
# It waits until no new file has arrived for QUIET_SECONDS, so a batch of 50
# files becomes one notification (and one workflow run), not 50.
# If the notification fails, it tries again after the next quiet period.
set -uo pipefail

dir=${WATCH_DIR:-/data/outbound}
quiet=${QUIET_SECONDS:-10}
: "${WEBHOOK_URL:?}" "${WEBHOOK_HOST:?}"
mkdir -p "$dir"

pending=1  # report anything already waiting when the pod starts
echo "watching $dir (quiet period ${quiet}s) -> $WEBHOOK_URL"

while true; do
  inotifywait -qq -t "$quiet" -e close_write -e moved_to "$dir"
  case $? in
    0) pending=1; continue ;;  # a file landed; restart the quiet timer
    2) ;;                      # quiet period elapsed
    *) echo "inotifywait failed; retrying in 5s"; sleep 5; continue ;;
  esac
  (( pending )) || continue

  n=$(find "$dir" -maxdepth 1 -type f -name '*.txt' | wc -l)
  if (( n == 0 )); then pending=0; continue; fi

  echo "$(date -Is) $n file(s) waiting; notifying xena"
  if curl -sf --max-time 10 \
      -H "Host: $WEBHOOK_HOST" \
      -H "Authorization: Bearer $(cat /webhook/token)" \
      -H 'Content-Type: application/json' \
      -d "{\"files\":$n,\"source\":\"$HOSTNAME\"}" \
      "$WEBHOOK_URL" >/dev/null; then
    pending=0
    echo "  notified"
  else
    echo "  notification failed; will retry after the next quiet period"
  fi
done
