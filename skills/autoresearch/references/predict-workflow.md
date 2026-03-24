# Predict Modu — Coklu-Persona On-Analiz

## Amac
Kod degisikligi YAPMAZ. Projeyi 5 farkli uzman gozuyle analiz edip oncelikli iyilestirme listesi cikarir.

## Personalar

### 1. Performance Expert
- Bottleneck'ler nerede?
- N+1 query, gereksiz re-render, buyuk bundle, yavas I/O
- "Bu 3 dosyayi optimize etsen %X iyilesir"

### 2. Security Auditor
- OWASP Top 10 taramasi (yuzeysel)
- "Bu 3 dosyada input validation eksik"
- Severity: CRITICAL/HIGH/MEDIUM/LOW

### 3. Developer Experience (DX) Advocate
- API ergonomisi, naming tutarliligi, dokumantasyon eksikligi
- "Bu fonksiyon 200 satir, 3'e bolunmeli"
- "Bu error mesaji hicbir sey anlatmiyor"

### 4. Maintainability Purist
- Tekrar eden kod (DRY ihlali)
- Karmasik control flow (cyclomatic complexity)
- Dead code, unused exports
- Test coverage bosluklar

### 5. Devil's Advocate
- Diger 4 personanin onerilerini sorgular
- "Performance fix'i okunabilirligi bozar mi?"
- "Security fix'i UX'i kotulestirir mi?"
- Anti-herd: cogunluk yanlis olabilir

## Calistirma

Her persona icin ayri Explore subagent:
```
"Sen [PERSONA]. Bu projeyi analiz et. En onemli 3 iyilestirmeyi oner.
Her oneri: dosya, sorun, onerilen fix, beklenen etki, risk.
Sadece gercek sorunlar — varsayimsal/teorik oneriler YASAK."
```

## Cikti

Write `.autoresearch/PREDICTIONS.md`:
```markdown
# Autoresearch Predictions

## Konsensus (3+ persona tarafindan onerilenler)
1. [dosya] — [sorun] — Onerenler: Perf, Security, DX

## Persona Bazli
### Performance Expert
1. ...
### Security Auditor
1. ...
(devami)

## Devil's Advocate Notlari
- "X onerisi Y riski tasiyor"

## Onerilen Autoresearch Sirasi
1. CRITICAL security fix'leri (security modu)
2. Build-breaking hatalar (fix modu)
3. Konsensus iyilestirmeler (run modu)
4. Persona-spesifik (ilgili mod)
```

Bu dosya sonraki `/autoresearch run` cagrisinda hedef secimini yonlendirir.
