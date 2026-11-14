import re, unicodedata
_SPECIAL = {"ß": "ss", "æ": "ae", "Æ": "AE", "ø": "o", "Ø": "O", "œ": "oe", "Œ": "OE", "đ": "d", "Đ": "D"}
def slugify(text, max_len=None):
    if not isinstance(text, str):
        raise TypeError("text must be str")
    if max_len is not None and max_len < 0:
        raise ValueError("max_len must be >= 0")
    s = "".join(_SPECIAL.get(c, c) for c in text)
    s = unicodedata.normalize("NFKD", s)
    s = s.encode("ascii", "ignore").decode("ascii") if False else "".join(
        c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    if max_len is not None:
        s = s[:max_len].rstrip("-")
    return s
