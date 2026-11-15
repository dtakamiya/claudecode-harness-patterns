import calendar
from datetime import datetime, timedelta

_MONTHS = {n: i + 1 for i, n in enumerate("JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC".split())}
_DOW = {n: i for i, n in enumerate("SUN MON TUE WED THU FRI SAT".split())}

def _val(tok, lo, hi, names):
    t = tok.upper()
    if names and t in names: v = names[t]
    elif tok.isdigit(): v = int(tok)
    else: raise ValueError(f"bad token {tok!r}")
    if not lo <= v <= hi: raise ValueError(f"out of range {tok!r}")
    return v

def _field(text, lo, hi, names=None):
    out = set(); restricted = text != "*"
    for item in text.split(","):
        if not item: raise ValueError("empty item")
        base, step = item, 1
        if "/" in item:
            base, st = item.split("/", 1)
            if not st.isdigit() or int(st) < 1: raise ValueError("bad step")
            step = int(st)
            if base.upper() in (names or {}): raise ValueError("name with step")
        if base == "*": a, b = lo, hi
        elif "-" in base:
            x, y = base.split("-", 1); a, b = _val(x, lo, hi, names), _val(y, lo, hi, names)
            if a > b: raise ValueError("reversed")
        else:
            a = _val(base, lo, hi, names); b = hi if "/" in item else a
        out.update(range(a, b + 1, step))
    return out, restricted

def _parse(expr):
    f = expr.split()
    if len(f) != 5: raise ValueError("need 5 fields")
    mi, _ = _field(f[0], 0, 59); h, _ = _field(f[1], 0, 23)
    dom, dr = _field(f[2], 1, 31); mo, _ = _field(f[3], 1, 12, _MONTHS)
    dow, wr = _field(f[4], 0, 7, _DOW)
    dow = {0 if d == 7 else d for d in dow}
    return mi, h, dom, dr, mo, dow, wr

def day_matches(expr_parsed, d):
    mi, h, dom, dr, mo, dow, wr = expr_parsed
    if d.month not in mo: return False
    wd = (d.weekday() + 1) % 7
    a, b = d.day in dom, wd in dow
    return (a or b) if (dr and wr) else (a if dr else (b if wr else True))

def next_run(expr, after):
    p = _parse(expr); mi, h = sorted(p[0]), sorted(p[1])
    t = after.replace(second=0, microsecond=0) + timedelta(minutes=1)
    limit = after + timedelta(days=366 * 8 + 3)
    day = t.replace(hour=0, minute=0)
    while day <= limit:
        if day_matches(p, day):
            for hh in h:
                for mm in mi:
                    c = day.replace(hour=hh, minute=mm)
                    if c >= t: return c
        day += timedelta(days=1)
    raise ValueError("no match within 8 years")
