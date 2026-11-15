# T3: cron next_run

Create `cron.py` exposing `next_run(expr: str, after: datetime.datetime) -> datetime.datetime` (Python 3.9, stdlib only, naive datetimes).

Returns the earliest datetime STRICTLY AFTER `after` (seconds/microseconds of `after` ignored: result is on a whole minute, > after) matching the 5-field expression `minute hour day-of-month month day-of-week` (fields separated by whitespace).

Field syntax (comma-separated list of items; each item is one of):
- `*`            all values
- `N`            single value
- `A-B`          inclusive range (A <= B)
- `*/S`, `A-B/S` step over the full range / the given range
- `N/S`          start at N, step S, up to the field maximum
Ranges: minute 0-59, hour 0-23, day-of-month 1-31, month 1-12, day-of-week 0-7 (both 0 and 7 mean Sunday).
Names (case-insensitive): months JAN..DEC, weekdays SUN..SAT, usable as single values and in ranges (e.g. `MON-FRI`, `jan,mar`). Names are NOT allowed with steps on the name itself other than in ranges (`MON-FRI/2` is OK).
Step S must be >= 1. Anything invalid (wrong field count, out-of-range, reversed range, bad token, empty list item) raises `ValueError`.

Day matching: if BOTH day-of-month and day-of-week are restricted (i.e. neither field is a bare `*`), a day matches when EITHER matches (classic cron OR rule). If only one is restricted, only that one applies. `*/2` in day-of-month counts as restricted (only a bare `*` is unrestricted).
Day-of-month values that do not exist in a month (e.g. 31 in April, 30 in February) simply never match in that month; `0 0 29 2 *` therefore fires only in leap years (Gregorian rules, so 2100 is not leap).
If no match exists within 8 years after `after`, raise `ValueError`.
