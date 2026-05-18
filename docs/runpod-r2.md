# RunPod And Cloudflare R2 Artifacts

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

## Download On RunPod

```bash
export R2_ENDPOINT_URL="https://bb8b1b9ffb067e41f5657c9f1400c42b.r2.cloudflarestorage.com"
export R2_BUCKET="tarteel-realtime"
export R2_ACCESS_KEY_ID="replace-with-r2-access-key-id"
export R2_SECRET_ACCESS_KEY="replace-with-r2-secret-access-key"

git clone https://github.com/moabdelmoez/tarteel-realtime.git /workspace/tarteel-realtime
cd /workspace/tarteel-realtime
uv run --with boto3 python scripts/r2_artifacts.py download data/tanzil/quran-simple-clean.txt
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114001.mp3
uv run --with boto3 python scripts/r2_artifacts.py download fixtures/local_audio/114002.mp3
ffmpeg -y -i fixtures/local_audio/114001.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114001.wav
ffmpeg -y -i fixtures/local_audio/114002.mp3 -ac 1 -ar 16000 -sample_fmt s16 fixtures/local_audio/114002.wav
```

## Bootstrap A Fresh Pod

From a RunPod shell:

```bash
export TARTEEL_DOWNLOAD_R2_ARTIFACTS=1
export R2_ENDPOINT_URL="https://bb8b1b9ffb067e41f5657c9f1400c42b.r2.cloudflarestorage.com"
export R2_BUCKET="tarteel-realtime"
export R2_ACCESS_KEY_ID="replace-with-r2-access-key-id"
export R2_SECRET_ACCESS_KEY="replace-with-r2-secret-access-key"
bash scripts/runpod_bootstrap.sh
```

When `TARTEEL_DOWNLOAD_R2_ARTIFACTS=1`, the bootstrap also downloads `114001.mp3` and `114002.mp3` and prepares mono 16 kHz PCM WAVs for the ASR smoke commands. Set `TARTEEL_PREPARE_AUDIO_WAVS=0` to skip conversion, or `TARTEEL_RUN_TESTS=0` when you only want clone, caches, artifact download, and compile checks.
