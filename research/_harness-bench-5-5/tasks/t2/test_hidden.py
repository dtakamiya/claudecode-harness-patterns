import unittest
from ttlcache import TTLCache

class Clock:
    def __init__(self): self.t = 0.0
    def __call__(self): return self.t

def mk(cap=2, ttl=10, clk=None):
    clk = clk or Clock()
    return TTLCache(cap, ttl, clock=clk), clk

class T(unittest.TestCase):
    def test_validation(self):
        for a in [(0, 1), (1, 0), (1, -1)]:
            with self.assertRaises(ValueError): TTLCache(*a)
        c, _ = mk()
        with self.assertRaises(ValueError): c.put("a", 1, ttl=0)
    def test_basic(self):
        c, _ = mk(); c.put("a", 1)
        self.assertEqual(c.get("a"), 1); self.assertEqual(c.get("z", 9), 9)
        self.assertEqual(c.stats(), {"hits": 1, "misses": 1, "evictions": 0, "expirations": 0})
    def test_expiry_boundary(self):
        c, k = mk(ttl=10); c.put("a", 1)
        k.t = 9.999; self.assertEqual(c.get("a"), 1)
        k.t = 10; self.assertIsNone(c.get("a"))
        self.assertEqual(c.stats()["expirations"], 1); self.assertEqual(c.stats()["misses"], 1)
    def test_get_does_not_extend(self):
        c, k = mk(ttl=10); c.put("a", 1); k.t = 6; c.get("a"); k.t = 10
        self.assertIsNone(c.get("a"))
    def test_put_resets_expiry_and_value(self):
        c, k = mk(ttl=10); c.put("a", 1); k.t = 8; c.put("a", 2); k.t = 15
        self.assertEqual(c.get("a"), 2)
    def test_per_call_ttl(self):
        c, k = mk(ttl=10); c.put("a", 1, ttl=2); c.put("b", 2); k.t = 3
        self.assertIsNone(c.get("a")); self.assertEqual(c.get("b"), 2)
    def test_lru_eviction(self):
        c, _ = mk(cap=2); c.put("a", 1); c.put("b", 2); c.get("a"); c.put("c", 3)
        self.assertIsNone(c.peek("b")); self.assertEqual(c.peek("a"), 1)
        self.assertEqual(c.stats()["evictions"], 1)
    def test_replace_never_evicts(self):
        c, _ = mk(cap=2); c.put("a", 1); c.put("b", 2); c.put("a", 3)
        self.assertEqual(c.stats()["evictions"], 0); self.assertEqual(len(c), 2)
    def test_replace_marks_mru(self):
        c, _ = mk(cap=2); c.put("a", 1); c.put("b", 2); c.put("a", 3); c.put("c", 4)
        self.assertIsNone(c.peek("b")); self.assertEqual(c.peek("a"), 3)
    def test_purge_before_evict(self):
        c, k = mk(cap=2, ttl=10); c.put("a", 1, ttl=1); c.put("b", 2); k.t = 5
        c.put("c", 3)
        s = c.stats(); self.assertEqual((s["expirations"], s["evictions"]), (1, 0))
        self.assertEqual(c.peek("b"), 2)
    def test_peek_no_recency_no_stats(self):
        c, _ = mk(cap=2); c.put("a", 1); c.put("b", 2); c.peek("a"); c.put("c", 3)
        self.assertIsNone(c.peek("a"))
        s = c.stats(); self.assertEqual((s["hits"], s["misses"]), (0, 0))
    def test_peek_expired_counts_expiration(self):
        c, k = mk(); c.put("a", 1); k.t = 10; self.assertIsNone(c.peek("a"))
        self.assertEqual(c.stats()["expirations"], 1); self.assertEqual(c.stats()["misses"], 0)
    def test_delete(self):
        c, k = mk(); c.put("a", 1); c.put("b", 2)
        self.assertTrue(c.delete("a")); self.assertFalse(c.delete("a"))
        k.t = 10; self.assertFalse(c.delete("b")); self.assertEqual(c.stats()["expirations"], 1)
    def test_len_purges(self):
        c, k = mk(cap=3); c.put("a", 1, ttl=1); c.put("b", 2); k.t = 2
        self.assertEqual(len(c), 1); self.assertEqual(c.stats()["expirations"], 1)
        self.assertEqual(len(c), 1); self.assertEqual(c.stats()["expirations"], 1)
    def test_contains(self):
        c, k = mk(); c.put("a", 1); self.assertIn("a", c); k.t = 10
        self.assertNotIn("a", c); self.assertEqual(c.stats()["expirations"], 1)
    def test_expired_entry_not_counted_toward_capacity(self):
        c, k = mk(cap=1, ttl=5); c.put("a", 1); k.t = 5; c.put("b", 2)
        self.assertEqual(c.stats()["evictions"], 0); self.assertEqual(c.peek("b"), 2)

if __name__ == "__main__": unittest.main()
