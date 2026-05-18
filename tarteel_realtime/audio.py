from __future__ import annotations

import struct


class PcmDecodeError(ValueError):
    pass


def pcm16le_to_float_samples(pcm: bytes) -> list[float]:
    if len(pcm) % 2 != 0:
        raise PcmDecodeError("PCM16 payload must contain an even number of bytes")

    sample_count = len(pcm) // 2
    if sample_count == 0:
        return []

    integers = struct.unpack(f"<{sample_count}h", pcm)
    return [sample / 32768 for sample in integers]
