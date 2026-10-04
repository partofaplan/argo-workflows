# Encrypted transfer between data centers

An Argo Workflows demo that moves files from one cluster ("data center") to
another as soon as they land. Each file is encrypted at the source, travels
only as ciphertext, and is decrypted and checksum-verified at the destination.

```
 hercules (k3d-hercules)                       xena (k3d-xena)
┌────────────────────────────┐          ┌─────────────────────────────────────────┐
│ landing-zone               │  1 HTTP  │ EventSource (webhook) ─► Sensor          │
│   /data/outbound ◄── drop  ├─────────►│                           └► Workflow    │
│   /data/sent, /conflicts   │          │                                          │
│   watcher sidecar          │  2 SSH   │ encrypt-and-send  (one pod per 10 files) │
│   sshd ◄───────────────────┼──────────┤   runs `age -r <xena pubkey>` ON hercules│
│                            │ ciphertext   streams only ciphertext ─┐             │
└────────────────────────────┘          │                            ▼             │
                                        │ landing-zone   /data/encrypted/*.age     │
                                        │                /data/inbound/*  ◄─┐      │
                                        │ decrypt-and-verify ───────────────┘      │
                                        │   xena's private key, SHA-256 check,     │
                                        │   then archives the original on hercules │
                                        └─────────────────────────────────────────┘
```

1. **Trigger**: the watcher sidecar on hercules uses inotify. After files stop
   arriving for 10 seconds, it POSTs the file count to a webhook in xena, with
   a bearer token. A Sensor turns that call into a Workflow. One batch becomes
   one run, not one run per file.
2. **discover**: lists `*.txt` in hercules `outbound/` over SSH and splits
   them into chunks of 10 (the `chunk-size` parameter).
3. **encrypt-and-send**, one pod per chunk with 6 chunks at a time. Each pod
   reuses one SSH connection per host for all its files. For each file, it:
   - fingerprints the plaintext on hercules (SHA-256)
   - runs `age` **on hercules** with xena's public key
   - streams the ciphertext to xena `encrypted/NAME.txt.age`, writing a temp
     name and then renaming it
   - checks that what landed is an age file

   Plaintext never leaves hercules. Hercules never holds a key that can decrypt.
4. **decrypt-and-verify**, one pod per chunk. For each file, it:
   - decrypts with xena's private key, a Secret that exists only in xena and is
     mounted only into this step
   - compares the SHA-256 against the original
   - writes `inbound/NAME.txt` using a temp name and rename
   - moves the original to `sent/` on hercules

   A file is archived on the source only after its decrypted copy checks out.
   If a step fails, Argo retries the whole chunk. Every action is safe to
   repeat, so files the chunk already finished are just checked again.
5. **summarize**: totals the plaintext bytes and the encrypted bytes sent.

A mutex means a run that's triggered while another is still going waits its
turn instead of fighting over the same files.

### Repeated file names

Before encrypting, each file is compared with `xena:inbound/<name>`. The
check runs again right before the decrypted copy is written.

| Situation | What happens |
|---|---|
| New name | Encrypted, sent, decrypted, verified; original → `sent/` |
| Same name, same content | **Duplicate**: not resent; original → `sent/` |
| Same name, different content | **Conflict**: not sent, and `xena:inbound/` is never overwritten. The original goes to `hercules:/data/conflicts/` with a `NAME.reason` file giving both checksums, for someone to review. |

Originals are archived by `lz-archive.sh`, which runs on hercules. It moves a
file only if its SHA-256 still matches the version the workflow handled. If
someone re-drops a file under the same name in the middle of a run, the new
version stays in `outbound/` for the next run instead of being filed as sent.
It also never overwrites a different file already in `sent/` or `conflicts/`;
it adds a timestamp to the name instead.

## How the two "data centers" reach each other

The clusters are on separate Docker networks. Each one reaches the other
through ports published on the host, which k3d names `host.k3d.internal`
inside every cluster:

| From → to | Address | Behind it |
|---|---|---|
| xena → hercules SSH | `host.k3d.internal:2322` | hercules k3d load balancer → NodePort 30022 |
| hercules → xena webhook | `host.k3d.internal:9080` with `Host: events.xena.internal` | xena's Traefik → EventSource service |

Both ports are also open on your Mac's network interfaces. The SSH server only
accepts the demo key. The webhook rejects calls without the token (401).

## Files

| File | What it is |
|---|---|
| `image/` | One Alpine image (sshd, ssh client, age, inotify) used by both landing zones and every workflow step, plus the landing-zone scripts: `lz-sshd.sh`, `lz-watch.sh` (the trigger) and `lz-archive.sh` (checksum-guarded archiving). `setup.sh` builds it and imports it into both clusters, so no registry is involved. |
| `00-landing-zone-hercules.yaml` | Source landing zone: sshd and the watcher sidecar, on a PVC |
| `01-landing-zone-xena.yaml` | Destination landing zone: sshd, on a PVC |
| `10-workflow-template.yaml` | The transfer pipeline |
| `20-events-xena.yaml` | EventBus, webhook EventSource, Traefik route, Sensor and its RBAC |
| `setup.sh` | Builds the image, generates keys into `.keys/` (gitignored), creates the Secrets, applies everything to both clusters |
| `drop-files.sh` | Drops N gibberish `.txt` files (default 50) on hercules, which triggers a run |
| `drop-repeats.sh` | Re-drops N exact copies and N same-name-new-content files (default 2 each), using names xena already has |
| `peek.sh` | Counts the files in each landing-zone directory |
| `teardown.sh` | Removes everything (keeps `.keys/`) |

## Run it

Prerequisites, all in xena: Argo Workflows (Helm chart `argo/argo-workflows`,
release `argo-workflows` in namespace `argo`) and Argo Events (chart
`argo/argo-events`).

```sh
./setup.sh           # contexts default to k3d-hercules and k3d-xena
./drop-files.sh      # 50 files land on hercules ...
./peek.sh            # ... about 40 seconds later they're in xena
```

Watch it in the Argo UI under *Workflows*. Runs are labelled
`app=cross-dc-transfer`, and the `files-reported` parameter shows what the
watcher saw. To see the encryption, open an `encrypt-and-send` pod's logs, or
compare a file in both places:

```sh
kubectl --context k3d-xena -n landing-zone exec deploy/landing-zone -- \
  sh -c 'f=$(ls /data/inbound | head -1); head -3 /data/encrypted/$f.age; echo; head -3 /data/inbound/$f'
```

## Things to show in a demo

- **Event-driven, not scheduled**: nothing polls. Drop files and a run starts
  about 10 seconds after the last one lands.
- **Batching**: `./drop-files.sh 50` gives one run with 5 chunks of 10 (10 transfer pods), not 50 runs. Pass `chunk-size` to change the grouping.
- **Encrypt at the source**: the `age` command runs on hercules. Xena's
  `encrypted/` holds only ciphertext, and only xena's Secret can decrypt it.
- **Verified handoff**: the original moves to `sent/` only after the
  decrypted copy's SHA-256 matches. Kill a pod mid-run. Argo retries that chunk, and
  any file that didn't finish stays in `outbound/` for the next run.
- **Overlap safety**: drop files twice in quick succession. The second run
  waits on the mutex, then picks up whatever is left.
- **Repeats**: run `./drop-repeats.sh && ./drop-files.sh 5`. The summary step
  reports 5 delivered, 2 duplicates skipped and 2 conflicts set aside. Then
  `./peek.sh` shows the conflicts on hercules. Each `.reason` file shows the
  existing and incoming checksums, and nothing in `xena:inbound/` changed.
