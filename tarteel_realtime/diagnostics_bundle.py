from __future__ import annotations

import json
import re
import struct
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


@dataclass(frozen=True)
class DiagnosticsBundle:
    path: Path
    index_html_path: Path
    trace_json_path: Path


_SAFE_QUERY_PARAMS = {"scope", "diagnostics"}
_SENSITIVE_KEYS = {"authorization", "bearer_token", "access_token", "token", "api_key"}


def scrub_url(url: str) -> str:
    parts = urlsplit(url)
    safe_query = []
    for name, value in parse_qsl(parts.query, keep_blank_values=True):
        if name in _SAFE_QUERY_PARAMS:
            safe_query.append((name, value))
        else:
            safe_query.append((name, "<redacted>"))
    netloc = parts.netloc.rsplit("@", 1)[-1]
    return urlunsplit(
        (
            parts.scheme,
            netloc,
            parts.path,
            urlencode(safe_query),
            "",
        )
    )


def build_waveform_peaks(
    pcm: bytes,
    *,
    bucket_samples: int = 320,
) -> list[dict[str, float]]:
    if bucket_samples <= 0:
        raise ValueError("bucket_samples must be positive")

    sample_count = len(pcm) // 2
    if sample_count == 0:
        return []

    samples = [
        sample
        for (sample,) in struct.iter_unpack("<h", pcm[: sample_count * 2])
    ]
    peaks: list[dict[str, float]] = []
    for offset in range(0, len(samples), bucket_samples):
        bucket = samples[offset : offset + bucket_samples]
        peaks.append(
            {
                "min": round(min(bucket) / 32768.0, 4),
                "max": round(max(bucket) / 32768.0, 4),
            }
        )
    return peaks


def write_diagnostics_bundle(
    *,
    output_root: Path,
    session_slug: str,
    trace: dict[str, Any],
    raw_audio_pcm: bytes,
    sample_rate_hz: int,
    asr_input_segments: list[dict[str, Any]],
    asr_windows: list[dict[str, Any]],
) -> DiagnosticsBundle:
    _validate_session_slug(session_slug)
    bundle_path = unique_bundle_path(output_root / session_slug)
    assets_path = bundle_path / "assets"
    asr_windows_path = bundle_path / "asr-windows"
    assets_path.mkdir(parents=True, exist_ok=True)
    asr_windows_path.mkdir(parents=True, exist_ok=True)

    raw_mic_filename = "raw-mic.wav"
    asr_input_filename = "asr-input.wav"

    write_pcm16_wav(
        bundle_path / raw_mic_filename,
        raw_audio_pcm,
        sample_rate_hz=sample_rate_hz,
    )

    asr_input_pcm = b"".join(segment["pcm"] for segment in asr_input_segments)
    write_pcm16_wav(
        bundle_path / asr_input_filename,
        asr_input_pcm,
        sample_rate_hz=sample_rate_hz,
    )

    normalized_windows: list[dict[str, Any]] = []
    for window in asr_windows:
        window_id = int(window["id"])
        filename = f"asr-window-{window_id:03d}.wav"
        pcm = window["pcm"]
        normalized = _sanitize_trace_value(
            {key: value for key, value in window.items() if key != "pcm"}
        )
        write_pcm16_wav(
            asr_windows_path / filename,
            pcm,
            sample_rate_hz=sample_rate_hz,
        )

        normalized["filename"] = f"asr-windows/{filename}"
        normalized["waveform_peaks"] = build_waveform_peaks(pcm)
        normalized_windows.append(normalized)

    normalized_trace = _sanitize_trace_value(trace)
    normalized_trace["asr_windows"] = normalized_windows
    normalized_trace["audio_artifacts"] = {
        "raw_mic": {
            "filename": raw_mic_filename,
            "waveform_peaks": build_waveform_peaks(raw_audio_pcm),
        },
        "asr_input": {
            "filename": asr_input_filename,
            "waveform_peaks": build_waveform_peaks(asr_input_pcm),
        },
    }

    trace_json_path = bundle_path / "trace.json"
    trace_json_path.write_text(
        json.dumps(
            normalized_trace,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    (assets_path / "diagnostics.css").write_text(
        DIAGNOSTICS_CSS,
        encoding="utf-8",
    )
    (assets_path / "diagnostics.js").write_text(
        DIAGNOSTICS_JS,
        encoding="utf-8",
    )

    index_html_path = bundle_path / "index.html"
    index_html_path.write_text(
        render_index_html(normalized_trace),
        encoding="utf-8",
    )

    return DiagnosticsBundle(
        path=bundle_path,
        index_html_path=index_html_path,
        trace_json_path=trace_json_path,
    )


def unique_bundle_path(path: Path) -> Path:
    if not path.exists():
        return path

    suffix = 2
    while True:
        candidate = path.with_name(f"{path.name}-{suffix}")
        if not candidate.exists():
            return candidate
        suffix += 1


def write_pcm16_wav(path: Path, pcm: bytes, *, sample_rate_hz: int) -> None:
    _validate_pcm16(pcm)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate_hz)
        wav_file.writeframes(pcm)


def render_index_html(trace: dict[str, Any]) -> str:
    encoded_trace = _json_for_inline_script(trace)
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Visual Diagnostics</title>
  <link rel="stylesheet" href="assets/diagnostics.css">
</head>
<body>
  <main>
    <header>
      <p class="eyebrow">Local recitation trace</p>
      <h1>Visual Diagnostics</h1>
      <p>This report is a local diagnostics bundle and may contain voice audio, transcripts, and timing traces.</p>
    </header>
    <section id="summary" aria-label="Summary"></section>
    <section id="playback" aria-label="Playback">
      <h2>Playback</h2>
      <div class="audio-grid">
        <label>Raw mic<audio controls src="raw-mic.wav"></audio></label>
        <label>ASR input<audio controls src="asr-input.wav"></audio></label>
      </div>
    </section>
    <section id="timeline" aria-label="Timeline"></section>
    <section aria-label="Detail">
      <h2>Detail</h2>
      <pre id="detail"></pre>
    </section>
  </main>
  <script type="application/json" id="trace-data">{encoded_trace}</script>
  <script src="assets/diagnostics.js"></script>
</body>
</html>
"""


def _validate_session_slug(session_slug: str) -> None:
    if not session_slug or session_slug in {".", ".."}:
        raise ValueError("session_slug must be a non-empty relative name")
    if Path(session_slug).name != session_slug:
        raise ValueError("session_slug must not contain path separators")
    if Path(session_slug).is_absolute():
        raise ValueError("session_slug must be relative")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", session_slug):
        raise ValueError("session_slug contains unsupported characters")


def _validate_pcm16(pcm: bytes) -> None:
    if len(pcm) % 2 != 0:
        raise ValueError("PCM16 audio must contain an even number of bytes")


def _sanitize_trace_value(value: Any) -> Any:
    if isinstance(value, dict):
        sanitized = {}
        for key, item in value.items():
            key_text = str(key)
            if _is_sensitive_key(key_text):
                sanitized[key_text] = "<redacted>"
            elif _is_url_key(key_text) and isinstance(item, str):
                sanitized[key_text] = scrub_url(item)
            else:
                sanitized[key_text] = _sanitize_trace_value(item)
        return sanitized
    if isinstance(value, list):
        return [_sanitize_trace_value(item) for item in value]
    if isinstance(value, tuple):
        return [_sanitize_trace_value(item) for item in value]
    if isinstance(value, bytes | bytearray | memoryview):
        raise TypeError("trace JSON must not contain raw bytes")
    return value


def _is_sensitive_key(key: str) -> bool:
    return key.lower() in _SENSITIVE_KEYS


def _is_url_key(key: str) -> bool:
    key_lower = key.lower()
    return key_lower == "url" or key_lower.endswith("_url")


def _json_for_inline_script(trace: dict[str, Any]) -> str:
    return (
        json.dumps(trace, ensure_ascii=False, sort_keys=True)
        .replace("<", "\\u003c")
        .replace(">", "\\u003e")
        .replace("&", "\\u0026")
    )


DIAGNOSTICS_CSS = """body {
  margin: 0;
  color: #18202a;
  background: #f5f7fa;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

main {
  max-width: 1120px;
  margin: 0 auto;
  padding: 28px 20px 48px;
}

header {
  margin-bottom: 20px;
  border-bottom: 1px solid #d8e0ea;
}

.eyebrow {
  margin: 0 0 4px;
  color: #536173;
  font-size: 0.8rem;
  text-transform: uppercase;
}

h1 {
  margin: 0 0 8px;
  font-size: 2rem;
}

h2 {
  margin: 22px 0 10px;
  font-size: 1.1rem;
}

.summary-grid,
.audio-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 12px;
}

.metric,
.lane {
  border: 1px solid #d8e0ea;
  background: white;
}

.metric {
  padding: 12px;
}

.metric strong {
  display: block;
  font-size: 1.3rem;
}

.lane {
  display: grid;
  grid-template-columns: 150px 1fr;
  gap: 12px;
  align-items: center;
  padding: 10px;
  margin-bottom: 8px;
}

.bar {
  height: 22px;
  background: linear-gradient(90deg, #3478f6, #2d9d78);
}

.chunk,
.window {
  margin: 2px;
  padding: 5px 8px;
  border: 1px solid #b8c4d2;
  background: #f9fbfd;
  color: #18202a;
  cursor: pointer;
}

label {
  display: block;
  color: #536173;
  font-size: 0.9rem;
}

audio {
  display: block;
  width: 100%;
  margin-top: 6px;
}

pre {
  min-height: 160px;
  margin: 0;
  padding: 12px;
  overflow: auto;
  color: white;
  background: #18202a;
  white-space: pre-wrap;
}
"""


DIAGNOSTICS_JS = """const trace = JSON.parse(document.getElementById("trace-data").textContent);
const summary = document.getElementById("summary");
const timeline = document.getElementById("timeline");
const detail = document.getElementById("detail");

function show(value) {
  detail.textContent = JSON.stringify(value || {}, null, 2);
}

function metric(label, value) {
  const card = document.createElement("div");
  const labelElement = document.createElement("span");
  const valueElement = document.createElement("strong");
  card.className = "metric";
  labelElement.textContent = label;
  valueElement.textContent = String(value);
  card.append(labelElement, valueElement);
  return card;
}

function lane(title, populate) {
  const row = document.createElement("div");
  const heading = document.createElement("strong");
  const content = document.createElement("div");
  row.className = "lane";
  heading.textContent = title;
  populate(content);
  row.append(heading, content);
  return row;
}

function addButtons(container, values, className, labelFor, emptyText) {
  if (!values.length) {
    container.textContent = emptyText;
    return;
  }
  values.forEach((value, index) => {
    const button = document.createElement("button");
    button.className = className;
    button.dataset.kind = className;
    button.dataset.index = String(index);
    button.textContent = String(labelFor(value, index));
    container.appendChild(button);
  });
}

const chunks = trace.chunks || [];
const windows = trace.asr_windows || [];
summary.className = "summary-grid";
summary.replaceChildren(
  metric("Chunks", chunks.length),
  metric("ASR windows", windows.length),
  metric("Raw artifact", trace.audio_artifacts?.raw_mic?.filename || "none"),
  metric("ASR artifact", trace.audio_artifacts?.asr_input?.filename || "none"),
);

timeline.appendChild(lane("Raw waveform", (content) => {
  const bar = document.createElement("div");
  bar.className = "bar";
  content.appendChild(bar);
}));
timeline.appendChild(lane("Chunks", (content) => {
  addButtons(content, chunks, "chunk", (chunk, index) => chunk.sequence_number ?? index, "No chunks recorded");
}));
timeline.appendChild(lane("ASR windows", (content) => {
  addButtons(content, windows, "window", (window) => window.id, "No ASR windows recorded");
}));

timeline.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-kind][data-index]");
  if (!button) return;
  const values = button.dataset.kind === "chunk" ? chunks : windows;
  show(values[Number(button.dataset.index)]);
});

show(trace.metadata || trace);
"""
