from __future__ import annotations

import argparse
import hashlib
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

REPO_ROOT = Path(__file__).resolve().parents[1]
SKIP_FILENAMES = {".DS_Store"}


@dataclass(frozen=True)
class R2Config:
    endpoint_url: str
    bucket: str
    access_key_id: str
    secret_access_key: str
    region: str = "auto"


def _required_env(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(
            f"Missing {name}. Use Cloudflare R2 S3 credentials, not a general Cloudflare API token."
        )
    return value


def load_r2_config() -> R2Config:
    return R2Config(
        endpoint_url=_required_env("R2_ENDPOINT_URL"),
        bucket=_required_env("R2_BUCKET"),
        access_key_id=_required_env("R2_ACCESS_KEY_ID"),
        secret_access_key=_required_env("R2_SECRET_ACCESS_KEY"),
        region=os.getenv("R2_REGION", "auto"),
    )


def default_object_key(path: Path) -> str:
    resolved = path.resolve()
    try:
        relative = resolved.relative_to(REPO_ROOT)
    except ValueError as exc:
        raise ValueError(f"{resolved} is outside the repository; pass --key explicitly.") from exc
    return relative.as_posix()


def iter_upload_files(source: Path) -> Iterable[Path]:
    if source.is_file():
        if source.name not in SKIP_FILENAMES:
            yield source
        return

    for path in sorted(source.rglob("*")):
        if path.is_file() and path.name not in SKIP_FILENAMES:
            yield path


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_s3_client(config: R2Config):
    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError("boto3 is required. Run with: uv run --with boto3 python scripts/r2_artifacts.py ...") from exc

    return boto3.client(
        "s3",
        endpoint_url=config.endpoint_url,
        aws_access_key_id=config.access_key_id,
        aws_secret_access_key=config.secret_access_key,
        region_name=config.region,
    )


def upload(source: Path, key: str | None) -> None:
    config = load_r2_config()
    client = make_s3_client(config)
    source = source.resolve()

    if not source.exists():
        raise FileNotFoundError(source)

    for path in iter_upload_files(source):
        object_key = key or default_object_key(path)
        if source.is_dir() and key:
            object_key = f"{key.rstrip('/')}/{path.relative_to(source).as_posix()}"
        client.upload_file(str(path), config.bucket, object_key)
        print(f"uploaded s3://{config.bucket}/{object_key} sha256={sha256_file(path)}")


def download(key: str, destination: Path | None) -> None:
    config = load_r2_config()
    client = make_s3_client(config)
    target = (destination or REPO_ROOT / key).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    client.download_file(config.bucket, key, str(target))
    print(f"downloaded s3://{config.bucket}/{key} -> {target} sha256={sha256_file(target)}")


def list_objects(prefix: str) -> None:
    config = load_r2_config()
    client = make_s3_client(config)
    paginator = client.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=config.bucket, Prefix=prefix):
        for item in page.get("Contents", []):
            print(f"{item['Key']}\t{item['Size']}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Upload, download, or list Cloudflare R2 artifacts.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    upload_parser = subparsers.add_parser("upload", help="Upload a file or directory.")
    upload_parser.add_argument("source", type=Path)
    upload_parser.add_argument("--key", help="R2 object key, or prefix when source is a directory.")

    download_parser = subparsers.add_parser("download", help="Download one object.")
    download_parser.add_argument("key")
    download_parser.add_argument("--destination", type=Path)

    list_parser = subparsers.add_parser("list", help="List objects.")
    list_parser.add_argument("--prefix", default="")

    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.command == "upload":
        upload(args.source, args.key)
    elif args.command == "download":
        download(args.key, args.destination)
    elif args.command == "list":
        list_objects(args.prefix)


if __name__ == "__main__":
    main()
