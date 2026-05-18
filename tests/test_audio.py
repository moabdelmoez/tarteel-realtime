import unittest

from tarteel_realtime.audio import PcmDecodeError, pcm16le_to_float_samples


class AudioDecodeTests(unittest.TestCase):
    def test_decodes_signed_pcm16_little_endian_to_float_samples(self):
        samples = pcm16le_to_float_samples(
            b"\x00\x00"      # 0
            b"\xff\x7f"      # 32767
            b"\x00\x80"      # -32768
            b"\x00\x40"      # 16384
        )

        self.assertEqual(samples[0], 0.0)
        self.assertAlmostEqual(samples[1], 32767 / 32768, places=6)
        self.assertEqual(samples[2], -1.0)
        self.assertEqual(samples[3], 0.5)

    def test_rejects_odd_length_pcm_payloads(self):
        with self.assertRaisesRegex(PcmDecodeError, "even number of bytes"):
            pcm16le_to_float_samples(b"\x00")
