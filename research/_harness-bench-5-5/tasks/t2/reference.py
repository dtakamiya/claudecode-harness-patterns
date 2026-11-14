import time
from collections import OrderedDict

class TTLCache:
    def __init__(self, capacity, ttl, clock=time.monotonic):
        if capacity < 1: raise ValueError("capacity")
        if ttl <= 0: raise ValueError("ttl")
        self._cap, self._ttl, self._clock = capacity, ttl, clock
        self._d = OrderedDict()  # key -> (value, expires_at)
        self._s = {"hits": 0, "misses": 0, "evictions": 0, "expirations": 0}

    def _expired(self, key):
        return self._clock() >= self._d[key][1]

    def _drop_if_expired(self, key):
        if key in self._d and self._expired(key):
            del self._d[key]
            self._s["expirations"] += 1
            return True
        return False

    def _purge(self):
        for k in [k for k in self._d if self._expired(k)]:
            del self._d[k]
            self._s["expirations"] += 1

    def put(self, key, value, ttl=None):
        t = self._ttl if ttl is None else ttl
        if t <= 0: raise ValueError("ttl")
        if key in self._d:
            del self._d[key]
        else:
            if len(self._d) >= self._cap:
                self._purge()
            if len(self._d) >= self._cap:
                self._d.popitem(last=False)
                self._s["evictions"] += 1
        self._d[key] = (value, self._clock() + t)

    def get(self, key, default=None):
        if key in self._d and not self._drop_if_expired(key):
            self._d.move_to_end(key)
            self._s["hits"] += 1
            return self._d[key][0]
        self._s["misses"] += 1
        return default

    def peek(self, key, default=None):
        if key in self._d and not self._drop_if_expired(key):
            return self._d[key][0]
        return default

    def delete(self, key):
        if key not in self._d: return False
        if self._drop_if_expired(key): return False
        del self._d[key]
        return True

    def __len__(self):
        self._purge()
        return len(self._d)

    def __contains__(self, key):
        return key in self._d and not self._drop_if_expired(key)

    def stats(self):
        return dict(self._s)
