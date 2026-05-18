from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import asdict
from dataclasses import dataclass
from pathlib import Path
from typing import TextIO

from tarteel_realtime.quran import QuranCorpus


DEFAULT_TANZIL_PATH = Path("data/tanzil/quran-simple-clean.txt")
DEFAULT_MANIFEST_PATH = Path("data/tanzil/quran-simple-clean.metadata.json")


@dataclass(frozen=True)
class TanzilManifest:
    format: str
    path: str
    source_name: str
    source_url: str
    sha256: str
    bytes: int
    ayah_count: int
    first_ref: str
    last_ref: str


def sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect_tanzil_file(
    path: str | Path,
    *,
    source_name: str = "",
    source_url: str = "",
) -> TanzilManifest:
    tanzil_path = Path(path)
    corpus = QuranCorpus.from_tanzil_file(tanzil_path)
    ayahs = corpus.ayahs()
    stat = tanzil_path.stat()

    return TanzilManifest(
        format="tanzil-pipe-v1",
        path=str(tanzil_path),
        source_name=source_name,
        source_url=source_url,
        sha256=sha256_file(tanzil_path),
        bytes=stat.st_size,
        ayah_count=len(ayahs),
        first_ref=str(ayahs[0].ref),
        last_ref=str(ayahs[-1].ref),
    )


def write_manifest(manifest: TanzilManifest, path: str | Path) -> None:
    manifest_path = Path(path)
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(asdict(manifest), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def load_manifest(path: str | Path) -> TanzilManifest:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    return TanzilManifest(**payload)


def validate_tanzil_file(
    tanzil_path: str | Path,
    manifest_path: str | Path,
) -> TanzilManifest:
    recorded = load_manifest(manifest_path)
    current = inspect_tanzil_file(
        tanzil_path,
        source_name=recorded.source_name,
        source_url=recorded.source_url,
    )
    if current.sha256 != recorded.sha256:
        raise ValueError(
            f"Tanzil checksum mismatch: expected {recorded.sha256}, got {current.sha256}"
        )
    return recorded


def main(argv: list[str] | None = None, stdout: TextIO | None = None) -> int:
    output = stdout if stdout is not None else sys.stdout
    parser = argparse.ArgumentParser(description="Inspect and validate local Tanzil Quran text metadata.")
    parser.add_argument("--tanzil-path", default=str(DEFAULT_TANZIL_PATH))
    parser.add_argument("--manifest-path", default=str(DEFAULT_MANIFEST_PATH))
    parser.add_argument("--source-name", default="")
    parser.add_argument("--source-url", default="")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--write-manifest", action="store_true")
    mode.add_argument("--check-manifest", action="store_true")
    args = parser.parse_args(argv)

    if args.check_manifest:
        manifest = validate_tanzil_file(args.tanzil_path, args.manifest_path)
    else:
        manifest = inspect_tanzil_file(
            args.tanzil_path,
            source_name=args.source_name,
            source_url=args.source_url,
        )
        if args.write_manifest:
            write_manifest(manifest, args.manifest_path)

    print(json.dumps(asdict(manifest), ensure_ascii=False, indent=2), file=output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
