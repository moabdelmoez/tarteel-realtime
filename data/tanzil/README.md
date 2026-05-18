# Tanzil Quran Text

Place the pinned full Quran Tanzil text here:

```text
data/tanzil/quran-simple-clean.txt
```

Expected row format:

```text
surah|ayah|text
```

Example:

```text
114|1|قُلْ أَعُوذُ بِرَبِّ النَّاسِ
```

After placing the file, generate local metadata:

```bash
uv run python -m tarteel_realtime.quran_data --tanzil-path data/tanzil/quran-simple-clean.txt --source-name Tanzil --source-url "record-the-source-url-you-used" --write-manifest
```

Before evaluation runs, check that the local file still matches the recorded checksum:

```bash
uv run python -m tarteel_realtime.quran_data --check-manifest
```

Do not edit `quran-simple-clean.txt` in place. If the matching pipeline needs normalized text later, create a derived artifact instead.
