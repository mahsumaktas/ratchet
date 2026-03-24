# Debug Modu — Bilimsel Bug Avlama

## Felsefe
Bug fix tahmin degil, bilimsel metot: gozlem → hipotez → deney → sonuc.

## Adimlar

### 1. Reproduce
- Kullanicinin raporladigi hatayi birebir reproduce et
- Reproduce edemiyorsan → daha fazla bilgi iste (log, stack trace, adimlar)
- Reproduce komutu/adimlarini kaydet — bu "donmus metrik" olacak

### 2. Minimize
- Hatanin en kucuk reproducer'ini bul
- Gereksiz kodu cikart, hatanin cekirdegine in
- "Bu 3 satiri commentlersem hata kayboluyor" seviyesine gel

### 3. 5 Whys
1. Neden hata olusuyor? → X fonksiyonu null donuyor
2. Neden null donuyor? → Y parametresi gecilmemis
3. Neden gecilmemis? → Z caller dogru format gondermiyor
4. Neden dogru format degil? → API spec'i degismis
5. Neden spec degisimi handle edilmemis? → **ROOT CAUSE: migration eksik**

### 4. Test-First Fix (TDD)
```
1. Failing test yaz (hatayi reproduce eden)
2. Testi calistir → FAIL (beklenen)
3. Fix'i uygula
4. Testi calistir → PASS
5. Tum testleri calistir → hepsi PASS (regresyon yok)
```

### 5. Ratchet Karari
- Test artik PASS + diger metrikler ayni/iyi → TUT
- Test PASS ama baska sey kirildi → AT, farkli yaklasim dene
- Test hala FAIL → AT, 5 Whys'i derinlestir

## Ozel Kurallar
- Her bug icin MAKSIMUM 3 fix denemesi. 3'te de basarisizsa → NOTES'a yaz, baska bug'a gec
- Bug fix sirasinda "bu da kalsin" diye ek degisiklik YAPMA — sadece bug fix
- Stack trace'deki TUM dosyalari oku, sadece hata veren satiri degil
