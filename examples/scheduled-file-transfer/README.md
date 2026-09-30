# Scheduled file transfer between servers

An Argo Workflows demo that moves files from one SFTP server to another every
5 minutes. It checksums every file and retries steps that fail.

```
 file-servers namespace                      argo namespace
┌──────────────────────────┐          ┌───────────────────────────────────┐
│ sftp-source              │          │ CronWorkflow  (*/5 * * * *)       │
│   data/outbound  ◄── new │◄─────────┤   └► WorkflowTemplate             │
│   data/archive     files │   SFTP   │        discover                   │
│   (generator sidecar)    │          │          ├► transfer × N files    │
├──────────────────────────┤          │          │    (4 at a time)       │
│ sftp-destination         │◄─────────┤          └► summarize             │
│   data/inbound           │          │        onExit: report             │
└──────────────────────────┘          └───────────────────────────────────┘
```

Each run:

1. **discover**: lists `data/outbound` on the source and picks up to 20 files matching `*.csv`.
2. **transfer**: starts one pod per file, with at most 4 running at once. Each pod:
   - downloads the file
   - uploads it to the destination as `.name.part`
   - renames it into place, so downstream readers never see a partial file
   - downloads the copy again and compares SHA-256
   - moves the original into `data/archive` on the source

   The original is archived only after the destination copy checks out. If
   something fails, the file stays in `outbound` and the next run picks it up.
3. **summarize**: collects the output from every transfer pod into one report.
4. **report** (exit handler): always runs, whether the workflow passed or failed.
   It lists failed attempts and fails loudly if the run failed. A real
   pipeline would send an alert from here.

## Files

| File | What it is |
|---|---|
| `00-file-servers.yaml` | Two SFTP servers standing in for the remote systems. The source has a sidecar that drops 1-3 CSVs every minute. |
| `10-workflow-template.yaml` | The reusable, parameterized transfer pipeline |
| `20-cron-workflow.yaml` | The schedule, which runs the template every 5 minutes (US Central time) |
| `setup.sh` | Generates SSH keys, creates the secrets, and applies everything |
| `run-now.sh` | Starts a run immediately and accepts parameter overrides |
| `peek.sh` | Lists the files currently on both servers |
| `teardown.sh` | Removes everything |

## Run it

```sh
./setup.sh                       # deploy (kube context "picard" by default)
./peek.sh                        # see files waiting on the source
./run-now.sh                     # don't wait for the schedule
./peek.sh                        # files are now in inbound + archive
```

Open the UI:

```sh
kubectl --context picard -n argo port-forward svc/argo-workflows-server 2746:2746
# http://localhost:2746  → Cron Workflows / Workflows / Workflow Templates
```

## Things to show in a demo

- **Scheduling**: open *Cron Workflows → sftp-file-transfer*. It shows the
  schedule, the time zone, and past runs. Other settings to point out:
  - `concurrencyPolicy: Forbid`: a slow run never overlaps the next one.
  - Suspend and resume the schedule from the UI.
- **Retries**: run `./run-now.sh chaos-percent=40`. Each transfer attempt then
  has a 40% chance of failing on purpose. The graph shows the failed attempts
  and the retries that recovered them, with exponential backoff (5s, 10s, 20s,
  and so on).
- **Failure handling**: run `./run-now.sh chaos-percent=90`. Most files run
  out of retries, the workflow fails, and the exit handler reports it. Those
  files are still in `outbound`, so the next run moves them.
- **Fan-out**: the number of transfer pods matches the number of files found,
  capped at 4 running at once.
- **Parameters**: use *Workflow Templates → Submit* to override any setting
  (host, directories, file pattern, batch size) without editing YAML. The same
  template could serve many server pairs, each with its own CronWorkflow.
- **Logs**: click any node to see its logs, for example each step of a
  transfer.

## Taking it further

- **Real servers**: point `source-host` and `destination-host` at them and put
  their keys in `sftp-client-credentials`. In production, pull that secret from
  Vault or External Secrets rather than generating it with `setup.sh`.
- **Other protocols**: only the image and the commands in `transfer-file`
  change. S3, SMB, FTPS, or rsync over SSH all work the same way.
- **Large files**: stream the transfer, or configure an artifact repository and
  use Argo artifacts, instead of downloading the whole file into the pod.
- **Alerts**: send the exit handler's report to Slack, Teams, or email.
- **Event-driven runs**: Argo Events can start the template when a file
  arrives, instead of polling on a schedule.
