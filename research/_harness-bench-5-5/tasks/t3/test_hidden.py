import unittest
from datetime import datetime as D, timedelta
from cron import next_run

def n(expr, s): return next_run(expr, D.fromisoformat(s))

class Cases(unittest.TestCase):
    def test_every_minute(self): self.assertEqual(n("* * * * *", "2024-01-01 00:00:00"), D(2024, 1, 1, 0, 1))
    def test_strictly_after_ignores_seconds(self): self.assertEqual(n("30 * * * *", "2024-01-01 00:30:45"), D(2024, 1, 1, 1, 30))
    def test_same_minute_not_returned(self): self.assertEqual(n("0 0 * * *", "2024-01-01 00:00:00"), D(2024, 1, 2, 0, 0))
    def test_step_minutes(self): self.assertEqual(n("*/15 * * * *", "2024-01-01 10:50:00"), D(2024, 1, 1, 11, 0))
    def test_range_step(self): self.assertEqual(n("10-40/10 * * * *", "2024-01-01 10:25:00"), D(2024, 1, 1, 10, 30))
    def test_n_slash_s(self): self.assertEqual(n("5/20 * * * *", "2024-01-01 10:06:00"), D(2024, 1, 1, 10, 25))
    def test_list(self): self.assertEqual(n("0,30 9,17 * * *", "2024-01-01 09:30:00"), D(2024, 1, 1, 17, 0))
    def test_month_rollover(self): self.assertEqual(n("0 0 1 * *", "2024-01-31 12:00:00"), D(2024, 2, 1, 0, 0))
    def test_year_rollover(self): self.assertEqual(n("0 0 1 1 *", "2024-06-01 00:00:00"), D(2025, 1, 1, 0, 0))
    def test_dom31_skips_short_months(self): self.assertEqual(n("0 0 31 * *", "2024-04-01 00:00:00"), D(2024, 5, 31, 0, 0))
    def test_feb30_never(self):
        with self.assertRaises(ValueError): n("0 0 30 2 *", "2024-01-01 00:00:00")
    def test_leap_day(self): self.assertEqual(n("0 0 29 2 *", "2024-03-01 00:00:00"), D(2028, 2, 29, 0, 0))
    def test_leap_day_skips_2100(self): self.assertEqual(n("0 0 29 2 *", "2097-01-01 00:00:00"), D(2104, 2, 29, 0, 0))
    def test_dow_names(self): self.assertEqual(n("0 9 * * MON-FRI", "2024-01-05 10:00:00"), D(2024, 1, 8, 9, 0))
    def test_dow_7_is_sunday(self): self.assertEqual(n("0 0 * * 7", "2024-01-01 00:00:00"), D(2024, 1, 7, 0, 0))
    def test_dow_0_is_sunday(self): self.assertEqual(n("0 0 * * 0", "2024-01-01 00:00:00"), D(2024, 1, 7, 0, 0))
    def test_month_names_lower(self): self.assertEqual(n("0 0 1 jan,mar *", "2024-01-01 00:00:00"), D(2024, 3, 1, 0, 0))
    def test_dow_range_step(self): self.assertEqual(n("0 0 * * MON-FRI/2", "2024-01-02 00:00:00"), D(2024, 1, 3, 0, 0))
    def test_or_rule(self):
        # 2024-01-01 is Monday. dom=15 OR dow=Mon
        self.assertEqual(n("0 0 15 * MON", "2024-01-02 00:00:00"), D(2024, 1, 8, 0, 0))
        self.assertEqual(n("0 0 15 * MON", "2024-01-14 00:00:00"), D(2024, 1, 15, 0, 0))
    def test_dom_only_restricted(self): self.assertEqual(n("0 0 15 * *", "2024-01-02 00:00:00"), D(2024, 1, 15, 0, 0))
    def test_dom_step_counts_restricted(self):
        # */2 dom is restricted -> OR with dow Sun
        self.assertEqual(n("0 0 */2 * SUN", "2024-01-02 00:00:00"), D(2024, 1, 3, 0, 0))
        self.assertEqual(n("0 0 */2 * SUN", "2024-01-06 00:00:00"), D(2024, 1, 7, 0, 0))
    def test_end_of_day(self): self.assertEqual(n("59 23 * * *", "2024-12-31 23:59:00"), D(2025, 1, 1, 23, 59))

class Invalid(unittest.TestCase):
    BAD = ["* * * *", "* * * * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * 32 * *", "* * * 13 *",
           "* * * * 8", "5-1 * * * *", "*/0 * * * *", "a * * * *", "1,,2 * * * *", ",1 * * * *", "1- * * * *",
           "* * * FOO *", "* * * * MON/2", "-1 * * * *", "*/ * * * *", "1-2-3 * * * *", ""]
    def test_bad(self):
        for e in self.BAD:
            with self.subTest(e=e):
                with self.assertRaises(ValueError): next_run(e, D(2024, 1, 1))

class Oracle(unittest.TestCase):
    """Independent brute-force minute scan with hand-written predicates (Sun=0 via isoweekday()%7)."""
    P = {
        "*/7 */5 * * *": lambda t: t.minute % 7 == 0 and t.hour % 5 == 0,
        "0 0 13 * FRI": lambda t: t.minute == 0 and t.hour == 0 and (t.day == 13 or t.isoweekday() == 5),
        "30 2 29 2 *": lambda t: (t.minute, t.hour, t.day, t.month) == (30, 2, 29, 2),
        "15 4 1,15 * *": lambda t: (t.minute, t.hour) == (15, 4) and t.day in (1, 15),
        "0 12 * 3-5 1-5": lambda t: (t.minute, t.hour) == (0, 12) and 3 <= t.month <= 5 and 1 <= t.isoweekday() <= 5,
        "45 23 31 * *": lambda t: (t.minute, t.hour, t.day) == (45, 23, 31),
        "0 0 */10 * *": lambda t: (t.minute, t.hour) == (0, 0) and (t.day - 1) % 10 == 0,
        "*/20 8-18/2 * * MON,WED": lambda t: t.minute % 20 == 0 and t.hour in (8, 10, 12, 14, 16, 18) and t.isoweekday() in (1, 3),
    }
    def test_oracle(self):
        for e, pred in self.P.items():
            for start in [D(2024, 1, 1), D(2024, 2, 28, 23, 50), D(2024, 12, 30, 12, 34, 56)]:
                t = start.replace(second=0, microsecond=0) + timedelta(minutes=1)
                while not pred(t): t += timedelta(minutes=1)
                with self.subTest(e=e, start=start):
                    self.assertEqual(next_run(e, start), t)

if __name__ == "__main__": unittest.main()
