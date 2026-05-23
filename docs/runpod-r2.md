# GPU Host (RunPod Example) And Cloudflare R2 Artifacts

Use GitHub for source code and Cloudflare R2 for local artifacts that should not live in git:

- `data/tanzil/quran-simple-clean.txt`
- `fixtures/local_audio/`
- future model or evaluation artifacts that are too large or private for git

## Credential Shape

The R2 helper uses Cloudflare R2 S3-compatible credentials:

```bash
export R2_ENDPOINT_URL="https://bb8b1b9ffb067e41f5657c9f1400c42b.r2.cloudflarestorage.com"
export R2_BUCKET="tarteel-realtime"
export R2_ACCESS_KEY_ID="replace-with-r2-access-key-id"
export R2_SECRET_ACCESS_KEY="replace-with-r2-secret-access-key"
```

Create those in Cloudflare with an R2 API token scoped to Object Read & Write for the `tarteel-realtime` bucket. Do not store these values in git. A general Cloudflare API token is not enough for the S3 client flow.

## Upload From The Mac

```bash
uv run --with boto3 python scripts/r2_artifacts.py upload data/tanzil/quran-simple-clean.txt
uv run --with boto3 python scripts/r2_artifacts.py upload fixtures/local_audio
uv run --with boto3 python scripts/r2_artifacts.py list
```

If `list` works but upload fails with `AccessDenied` during `PutObject`, recreate or edit the R2 S3 token so it has Object Read & Write access to the `tarteel-realtime` bucket.

## Download On A GPU Host

The current repo is public, so a fresh host can clone it over HTTPS. Put the R2 exports in a local env file and source them inside the host shell (for RunPod, use `/workspace/tarteel-r2.env`). Do not use `scp` for this workflow.

```bash
source /workspace/tarteel-r2.env

git clone https://github.com/moabdelmoez/tarteel-realtime.git /workspace/tarteel-realtime
cd /workspace/tarteel-realtime
uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114001.mp3
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114002.mp3
ffmpeg -y -i fixtures/local_audio/114001.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114001.wav
ffmpeg -y -i fixtures/local_audio/114002.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114002.wav
```

## Bootstrap A Fresh GPU Host

From a host shell (RunPod example):

```bash
source /workspace/tarteel-r2.env
export TARTEEL_DOWNLOAD_ARTIFACTS=1
bash scripts/gpu_bootstrap.sh
```

When `TARTEEL_DOWNLOAD_ARTIFACTS=1`, the bootstrap also downloads `114001.mp3` and `114002.mp3` and prepares mono 16 kHz PCM WAVs for the ASR smoke commands. Set `TARTEEL_PREPARE_AUDIO_WAVS=0` to skip conversion, or `TARTEEL_RUN_TESTS=0` when you only want clone, caches, artifact download, and compile checks.

`TARTEEL_DOWNLOAD_R2_ARTIFACTS=1` and `scripts/runpod_bootstrap.sh` are still supported as compatibility aliases.

## Private GitHub Repos On RunPod

The default `TARTEEL_REPO_URL` is an HTTPS GitHub URL. This works while the repo remains public. If the repository becomes private, a fresh pod cannot clone it without GitHub credentials. The bootstrap sets `GIT_TERMINAL_PROMPT=0` so missing auth fails fast instead of hanging at a username/password prompt.

Preferred setup for private repos:

```bash
ssh-keygen -t ed25519 -f /workspace/tarteel-realtime-deploy -N "" -C "runpod-tarteel-readonly"
cat /workspace/tarteel-realtime-deploy.pub
```

Add the printed public key to GitHub as a read-only deploy key for `moabdelmoez/tarteel-realtime`, then run:

```bash
export GIT_SSH_COMMAND="ssh -i /workspace/tarteel-realtime-deploy -o StrictHostKeyChecking=accept-new"
export TARTEEL_REPO_URL="git@github.com:moabdelmoez/tarteel-realtime.git"
export TARTEEL_DOWNLOAD_ARTIFACTS=1
export TARTEEL_RUN_TESTS=0
bash scripts/gpu_bootstrap.sh
```

Do not stream `.env` into the RunPod SSH gateway from an automated PTY; the gateway can echo stdin before the shell is ready. Prefer RunPod environment variables/secrets or paste exports manually into `/workspace/tarteel-r2.env` inside the pod.
