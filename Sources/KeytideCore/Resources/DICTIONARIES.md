# Bundled dictionaries

`words.lex` is a modified, normalized and expanded word list from LibreOffice dictionaries,
revision `32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4`:

- RU: Alexander I. Lebedev's `ru_RU/ru_RU.dic` and `.aff`.
- EN: SCOWL `en/en_US.dic` and `.aff`.
- Modern vocabulary: `scripts/dictionary-extra.txt` in Keytide.

Upstream: https://github.com/LibreOffice/dictionaries/tree/32b006a2c22a4ac7e8ed3f03346f7b3d85a970a4

Original notices and terms accompany the binary in `LICENSE_ru.txt` and `LICENSE_en.txt`.
These dictionaries retain their original licenses, independently of the application license.

Reproduce the binary using Python 3.9+ and no installed packages:

```sh
python3 scripts/build-dictionary.py
```

The developer script downloads only pinned, SHA-256-verified sources. Normal builds use the
checked-in binary and need no network or Python. The application memory-maps a validated
acyclic graph and follows at most 64 letters per lookup. There is no runtime Hunspell,
morphology expansion, dictionary process or network access. The word list provides exact
recognition, not typo suggestions; the native macOS checker handles unknown words.
