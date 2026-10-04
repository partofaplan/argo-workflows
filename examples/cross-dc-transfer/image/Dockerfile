# One small image used everywhere in the demo:
#   - the landing-zone hosts in both clusters (sshd + the file watcher)
#   - the Argo workflow steps (ssh client + age)
# setup.sh builds it and imports it into both k3d clusters, so nothing is pulled
# from a registry.
FROM alpine:3.22

RUN apk add --no-cache bash coreutils openssh-server openssh-client age jq curl inotify-tools \
 # "lz" owns the landing zone. New Alpine accounts are locked ("!"), and sshd
 # refuses even key logins for locked accounts, so mark it "no password" instead.
 && adduser -D -h /data -s /bin/bash -u 1000 lz \
 && sed -i 's/^lz:!:/lz:*:/' /etc/shadow

COPY sshd_config /etc/ssh/sshd_config
COPY lz-sshd.sh lz-watch.sh /usr/local/bin/
