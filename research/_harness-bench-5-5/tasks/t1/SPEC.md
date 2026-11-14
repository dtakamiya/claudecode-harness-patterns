# T1: slugify

Create `slug.py` exposing `slugify(text: str, max_len: int | None = None) -> str` (Python 3.9, stdlib only).

Rules:
1. Fold accented Latin letters to ASCII (`é` -> `e`, `ß` -> `ss`, `Æ` -> `ae`); characters with no ASCII fold that are not letters/digits are treated as separators.
2. Lowercase.
3. Every run of non-[a-z0-9] characters becomes a single `-`.
4. No leading or trailing `-`.
5. If `max_len` is given, truncate to at most `max_len` characters, then strip any trailing `-` again. Cut at a character boundary (no word-aware logic).
6. `max_len` of 0 returns `""`. Negative `max_len` raises `ValueError`. Non-str `text` raises `TypeError`.
7. Empty or all-separator input returns `""`.
