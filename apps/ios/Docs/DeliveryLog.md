# Delivery re-kick log

The TestFlight lane triggers on `paths: apps/ios/**` — an empty commit
never starts a run, so each upload retry after Apple's daily cap (error
90382) rides a dated line in this file. The build number does NOT bump on
a re-kick: the same undelivered train re-attempts until pilot accepts it.

- 2026-07-20 ~08:05Z — retry for build 1172 (b93c5d6; caps hit 04:40Z and
  earlier; carries 1165→1172).
- 2026-07-20 08:33Z — still 90382 (archive+export green again); next retry ~12:15Z.
- 2026-07-20 — user-requested immediate retry for build 1172.
- 2026-07-20 10:40Z — DELIVERED: pilot accepted build 1172 (carries 1165→1172).
- 2026-07-20 11:41Z — DELIVERED: build 1173 (Fundal page + pinned atmospheres + sky quality pass).
- 2026-07-20 13:05Z — retry 1176: 1174 a picat cu 90721 (cert revocat la
  upload), 1175 cu "Signing certificate is invalid" la export — ambele cu
  certificate create de propriul run cu ~15 min înainte. Suspiciune:
  revocare automată Apple după churn-ul de certificate de azi. 1176 e al
  treilea punct de măsurătoare; dacă pică la fel, trecem pe certificat
  persistent (P12 în secrete) în loc de revoke+create per run.
