#!/bin/bash
# Landing-zone host: installs the keys mounted from Secrets, creates the
# directories listed in LZ_DIRS under /data, then runs sshd in the foreground.
set -euo pipefail

install -m 600 /keys/host/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key
install -d -m 755 /etc/ssh/authorized_keys
install -m 644 /keys/client/client.pub /etc/ssh/authorized_keys/lz

for d in ${LZ_DIRS:?set LZ_DIRS, e.g. "outbound sent"}; do
  mkdir -p "/data/$d"
done
chown -R lz:lz /data

echo "landing zone ready: /data/{${LZ_DIRS// /,}}"
exec /usr/sbin/sshd -D -e
