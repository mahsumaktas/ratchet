# State Machine Referansi

## State'ler ve Gecerli Gecisler

```
BOOTSTRAP
  → SELECT_TARGET (basarili bootstrap sonrasi)

SELECT_TARGET
  → READ_FILE (hedef secildi)
  → STOP (durma kosulu saglandi)

READ_FILE
  → MAKE_CHANGE (dosya okundu, degisiklik planlandi)
  → SELECT_TARGET (dosya boundary'de veya okunamadi → skip)

MAKE_CHANGE
  → VALIDATE (degisiklik yapildi)
  → REVERT (degisiklik yapilamadi / bos degisiklik)

VALIDATE
  → DECIDE (metrikler olculdu)

DECIDE
  → COMMIT (TUT karari)
  → REVERT (AT karari)

COMMIT
  → LOG (commit basarili)

REVERT
  → LOG (revert basarili)

LOG
  → SELECT_TARGET (devam)
  → STRATEGY_CHANGE (5 ardisik discard)
  → STOP (durma kosulu)

STRATEGY_CHANGE
  → SELECT_TARGET (yeni strateji ile devam)
  → STOP (10 ardisik discard)

STOP
  → (terminal state — SUMMARY yaz)
```

## Gecersiz Gecisler (IMKANSIZ)
- SELECT_TARGET → COMMIT (olcum olmadan commit YOK)
- MAKE_CHANGE → DECIDE (validate olmadan karar YOK)
- VALIDATE → COMMIT (decide olmadan commit YOK)
- BOOTSTRAP → MAKE_CHANGE (hedef secimi olmadan degisiklik YOK)

## State Persistence
Her state gecisinde `state.json`'daki `"state"` field'i guncellenir.
Context reset sonrasi bu field'den devam edilir.
