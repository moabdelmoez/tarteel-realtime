from __future__ import annotations

import argparse
import asyncio
from copy import deepcopy
from datetime import UTC, datetime
import json
import os
from pathlib import Path
import re
import sys
from time import monotonic
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from tarteel_realtime.diagnostics_bundle import scrub_url, write_diagnostics_bundle
from tarteel_realtime.replay_probe import load_replay_audio_file, url_with_scope
from tarteel_realtime.ws_client import (
    build_chunk_payload,
    split_pcm_audio,
    websocket_connect_kwargs,
)


class DiagnosticCaptureError(RuntimeError):
    pass


def session_slug(
    *,
    timestamp_utc: str,
    audio_path: Path,
    scope: str | None,
) -> str:
    audio_slug = _slug_groups(audio_path.stem, fallback="audio")
    scope_slug = "auto" if not scope else _slug_groups(scope, fallback="scope")
    return f"{timestamp_utc}-{audio_slug}-scope-{scope_slug}"


def validate_trace_envelope(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("kind") != "recitation_trace":
        raise DiagnosticCaptureError(
            "Backend did not return recitation_trace envelopes; "
            "use a diagnostics-enabled backend with diagnostics=1."
        )
    if not isinstance(payload.get("trace"), dict):
        raise DiagnosticCaptureError("Invalid recitation_trace envelope: trace must be an object.")
    if not isinstance(payload.get("event"), dict):
        raise DiagnosticCaptureError("Invalid recitation_trace envelope: event must be an object.")
    return payload


def reconstruct_asr_windows(
    envelopes: list[dict[str, Any]],
    chunks: dict[int, bytes],
) -> list[dict[str, Any]]:
    windows: dict[int, bytes] = {}
    for envelope in envelopes:
        trace = envelope.get("trace")
        if not isinstance(trace, dict):
            continue
        window = trace.get("asr_window")
        if not isinstance(window, dict):
            continue
        window_id = int(window["id"])
        if window_id in windows:
            continue

        pieces: list[bytes] = []
        for segment in window.get("segments", []):
            sequence_number = int(segment["sequence_number"])
            start_byte = int(segment["start_byte"])
            end_byte = int(segment["end_byte"])
            pieces.append(chunks[sequence_number][start_byte:end_byte])
        windows[window_id] = b"".join(pieces)

    return [
        {"id": window_id, "pcm": pcm}
        for window_id, pcm in sorted(windows.items())
    ]


def merge_trace_records(
    *,
    metadata: dict[str, Any],
    envelopes: list[dict[str, Any]],
    client_chunks: list[dict[str, Any]],
) -> dict[str, Any]:
    client_by_sequence = {
        int(chunk["sequence_number"]): chunk
        for chunk in client_chunks
    }
    chunks: list[dict[str, Any]] = []
    for envelope in envelopes:
        trace = deepcopy(envelope["trace"])
        sequence_number = int(trace["sequence_number"])
        trace.update(client_by_sequence.get(sequence_number, {}))
        trace["event"] = deepcopy(envelope["event"])
        chunks.append(trace)

    return {
        "metadata": metadata,
        "chunks": chunks,
        "asr_windows": [],
        "audio_artifacts": {},
        "raw_backend_envelopes": envelopes,
    }


async def run_capture(
    *,
    url: str,
    audio_path: Path,
    chunk_ms: int,
    scope: str | None,
    output_root: Path,
    raw_sample_rate_hz: int,
    disable_ping: bool,
    bearer_token: str | None,
    authorization_source: str,
) -> Path:
    import websockets

    _validate_capture_inputs(chunk_ms=chunk_ms)
    audio = load_replay_audio_file(
        audio_path,
        raw_sample_rate_hz=raw_sample_rate_hz,
    )
    if not audio.pcm:
        raise DiagnosticCaptureError("Cannot capture diagnostics for empty audio input.")
    diagnostic_url = prepare_diagnostic_url(url, scope=scope)
    chunks = split_pcm_audio(audio, chunk_duration_ms=chunk_ms)
    if not chunks:
        raise DiagnosticCaptureError("Cannot capture diagnostics because audio produced no chunks.")
    chunk_bytes_by_sequence = {
        sequence_number: pcm
        for sequence_number, pcm in enumerate(chunks)
    }

    started_at = datetime.now(UTC)
    envelopes: list[dict[str, Any]] = []
    client_chunks: list[dict[str, Any]] = []

    try:
        async with websockets.connect(
            diagnostic_url,
            **websocket_connect_kwargs(
                disable_ping=disable_ping,
                authorization_token=bearer_token,
            ),
        ) as websocket:
            start = monotonic()
            for sequence_number, pcm in enumerate(chunks):
                capture_offset_ms = sequence_number * chunk_ms
                await _sleep_until_offset(start, capture_offset_ms)
                send_offset_ms = _elapsed_ms(start)
                payload = build_chunk_payload(
                    sequence_number=sequence_number,
                    pcm=pcm,
                    sample_rate_hz=audio.sample_rate_hz,
                )
                await websocket.send(json.dumps(payload))
                response_text = await websocket.recv()
                receive_offset_ms = _elapsed_ms(start)
                envelope = decode_trace_envelope(response_text)
                envelopes.append(envelope)
                client_chunks.append(
                    {
                        "sequence_number": sequence_number,
                        "capture_offset_ms": capture_offset_ms,
                        "send_offset_ms": send_offset_ms,
                        "receive_offset_ms": receive_offset_ms,
                        "roundtrip_ms": receive_offset_ms - send_offset_ms,
                        "pcm_bytes": len(pcm),
                        "sample_rate_hz": audio.sample_rate_hz,
                    }
                )
    except DiagnosticCaptureError:
        raise
    except Exception as exc:
        raise DiagnosticCaptureError(
            "WebSocket capture failed for "
            f"{scrub_url(diagnostic_url)}: {type(exc).__name__}"
        ) from None

    ended_at = datetime.now(UTC)
    metadata = {
        "diagnostic_tool_version": 1,
        "privacy_warning": "This local bundle contains voice audio and ASR transcripts.",
        "backend_url": scrub_url(diagnostic_url),
        "scope": scope,
        "audio_path": str(audio_path),
        "sample_rate_hz": audio.sample_rate_hz,
        "chunk_ms": chunk_ms,
        "authorization_used": bool(bearer_token),
        "authorization_source": authorization_source,
        "started_at_utc": _iso_utc(started_at),
        "ended_at_utc": _iso_utc(ended_at),
    }
    trace = merge_trace_records(
        metadata=metadata,
        envelopes=envelopes,
        client_chunks=client_chunks,
    )
    asr_windows = reconstruct_asr_windows(envelopes, chunk_bytes_by_sequence)
    asr_input_segments = [
        {"pcm": chunk_bytes_by_sequence[int(chunk["sequence_number"])]}
        for chunk in trace["chunks"]
        if (chunk.get("buffer") or {}).get("appended") is True
    ]

    bundle = write_diagnostics_bundle(
        output_root=output_root,
        session_slug=session_slug(
            timestamp_utc=started_at.strftime("%Y%m%dT%H%M%SZ"),
            audio_path=audio_path,
            scope=scope,
        ),
        trace=trace,
        raw_audio_pcm=audio.pcm,
        sample_rate_hz=audio.sample_rate_hz,
        asr_input_segments=asr_input_segments,
        asr_windows=asr_windows,
    )
    return bundle.index_html_path


def bearer_token_from_args(args: argparse.Namespace) -> tuple[str | None, str]:
    if args.bearer_token_env:
        token = os.environ.get(args.bearer_token_env, "")
        return (token or None), "environment"
    if args.bearer_token:
        return args.bearer_token, "argument"
    return None, "none"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Capture a replayed recitation diagnostics bundle.",
    )
    parser.add_argument("--url", required=True)
    parser.add_argument("--scope", default=None)
    parser.add_argument("--audio-path", type=Path, required=True)
    parser.add_argument("--chunk-ms", type=int, default=1_000)
    parser.add_argument("--sample-rate", type=int, default=16_000)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("diagnostics/sessions"),
    )
    parser.add_argument("--bearer-token", default=None)
    parser.add_argument("--bearer-token-env", default=None)
    parser.add_argument("--disable-ping", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    bearer_token, authorization_source = bearer_token_from_args(args)
    try:
        index_html_path = asyncio.run(
            run_capture(
                url=args.url,
                audio_path=args.audio_path,
                chunk_ms=args.chunk_ms,
                scope=args.scope,
                output_root=args.output_root,
                raw_sample_rate_hz=args.sample_rate,
                disable_ping=args.disable_ping,
                bearer_token=bearer_token,
                authorization_source=authorization_source,
            )
        )
    except DiagnosticCaptureError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    print(index_html_path.resolve())
    return 0


def prepare_diagnostic_url(url: str, *, scope: str | None) -> str:
    scoped_url = url_with_scope(url, scope)
    parts = urlsplit(scoped_url)
    if "@" in parts.netloc:
        raise DiagnosticCaptureError(
            f"WebSocket URL userinfo is not supported: {scrub_url(scoped_url)}"
        )
    return _url_with_diagnostics(scoped_url)


def _url_with_diagnostics(url: str) -> str:
    parts = urlsplit(url)
    query_items = [
        (name, value)
        for name, value in parse_qsl(parts.query, keep_blank_values=True)
        if name != "diagnostics"
    ]
    query_items.append(("diagnostics", "1"))
    return urlunsplit(
        (
            parts.scheme,
            parts.netloc,
            parts.path,
            urlencode(query_items),
            "",
        )
    )


def decode_trace_envelope(response_text: str) -> dict[str, Any]:
    try:
        payload = json.loads(response_text)
    except json.JSONDecodeError as exc:
        raise DiagnosticCaptureError(
            "Backend returned a non-JSON response instead of a diagnostics trace envelope."
        ) from exc
    if not isinstance(payload, dict):
        raise DiagnosticCaptureError("Backend returned a non-object diagnostics response.")
    return validate_trace_envelope(payload)


def _validate_capture_inputs(*, chunk_ms: int) -> None:
    if chunk_ms <= 0:
        raise DiagnosticCaptureError("--chunk-ms must be positive.")


async def _sleep_until_offset(start: float, offset_ms: int) -> None:
    sleep_ms = offset_ms - _elapsed_ms(start)
    if sleep_ms > 0:
        await asyncio.sleep(sleep_ms / 1_000)


def _elapsed_ms(start: float) -> int:
    return int(round((monotonic() - start) * 1_000))


def _iso_utc(value: datetime) -> str:
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def _slug_groups(value: str, *, fallback: str) -> str:
    return "-".join(re.findall(r"[A-Za-z0-9]+", value)) or fallback


if __name__ == "__main__":
    raise SystemExit(main())
