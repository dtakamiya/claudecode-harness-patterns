import re, unicodedata
_SPECIAL = {"ß": "ss", "æ": "ae", "Æ": "AE", "ø": "o", "Ø": "O", "œ": "oe", "Œ": "OE", "đ": "d", "Đ": "D"}
def slugify(text, max_len=None):
    if not isinstance(text, str):
        raise TypeError("text must be str")
    if max_len is not None and max_len < 0:
        raise ValueError("max_len must be >= 0")
    s = "".join(_SPECIAL.get(c, c) for c in text)
    s = unicodedata.normalize("NFKD", s)
    # 結合文字だけを除く。ASCII 化しない文字（日本語など）は後段の正規表現で区切りになる
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")
    if max_len is not None:
        s = s[:max_len].rstrip("-")
    return s
