# Delivery re-kick log

The TestFlight lane triggers on `paths: apps/ios/**` — an empty commit
never starts a run, so each upload retry after Apple's daily cap (error
90382) rides a dated line in this file. The build number does NOT bump on
a re-kick: the same undelivered train re-attempts until pilot accepts it.

- 2026-07-20 ~08:05Z — retry for build 1172 (b93c5d6; caps hit 04:40Z and
  earlier; carries 1165→1172).
- 2026-07-20 08:33Z — still 90382 (archive+export green again); next retry ~12:15Z.
- 2026-07-20 — user-requested immediate retry for build 1172.
