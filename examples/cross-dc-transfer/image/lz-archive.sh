#!/bin/bash
# Runs on the source landing zone (over SSH, from the workflow):
#   lz-archive.sh DIR FILE SHA256 [REASON]
#
# Moves outbound/FILE into DIR/ (sent or conflicts), but only if it's still the
# version the workflow handled. If a new file was dropped under the same name in
# the meantime, its checksum differs, so it stays in outbound/ for the next run.
# Never overwrites a different file already in DIR/; it adds a timestamp instead.
# REASON, if given, is saved next to the file as FILE.reason.
set -euo pipefail
dir=$1 f=$2 sha=$3 reason=${4:-}
[[ $dir == sent || $dir == conflicts ]] || { echo "unknown dir: $dir" >&2; exit 2; }
[[ $f =~ ^[A-Za-z0-9._-]+$ ]] || { echo "unsafe name: $f" >&2; exit 2; }
cd /data

if [[ ! -f outbound/$f ]]; then
  echo "outbound/$f is already gone (archived on an earlier attempt)"
  exit 0
fi
if [[ $(sha256sum "outbound/$f" | cut -d' ' -f1) != "$sha" ]]; then
  echo "outbound/$f changed since it was read; leaving it for the next run"
  exit 0
fi

dest="$dir/$f"
if [[ -e $dest ]] && ! cmp -s "outbound/$f" "$dest"; then
  dest="$dir/$(date -u +%Y%m%dT%H%M%SZ)-$f"
fi
mkdir -p "$dir"
mv "outbound/$f" "$dest"
if [[ -n $reason ]]; then printf '%s\n' "$reason" > "$dest.reason"; fi
echo "outbound/$f -> $dest"
