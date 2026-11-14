# T2: TTLCache

Create `ttlcache.py` exposing `class TTLCache` (Python 3.9, stdlib only).

`TTLCache(capacity: int, ttl: float, clock=time.monotonic)`
- `capacity` must be >= 1, `ttl` must be > 0; otherwise `ValueError`.
- `clock` is a zero-arg callable returning the current time (injected for tests).

Methods:
- `put(key, value, ttl=None)`: store. Per-call `ttl` overrides the default (must be > 0 else `ValueError`).
  Putting an existing key replaces its value, resets its expiry, and marks it most-recently-used.
  An entry is expired when `clock() >= expires_at` (expiry instant itself is already expired).
- `get(key, default=None)`: return value if present and not expired, marking it most-recently-used.
  An expired entry is removed on access and counts as an expiration AND a miss.
  Reading does NOT extend expiry.
- `peek(key, default=None)`: like `get` but does not change recency and does not touch hit/miss stats
  (an expired entry is still removed and counted as an expiration).
- `delete(key) -> bool`: remove a live entry and return True. A missing key returns False. An expired entry is removed, counted as an expiration, and returns False.
- `__len__`: number of live (non-expired) entries; purges expired entries first (each counted as an expiration).
- `__contains__`: same liveness rule as `peek`, no stats change besides expirations.
- `stats() -> dict` with integer keys `hits`, `misses`, `evictions`, `expirations`.

Capacity: when `put` adds a NEW key and the cache is full, first purge all expired entries (counted as expirations);
if still full, evict the least-recently-used live entry (counted as an eviction). Replacing an existing key never evicts.
