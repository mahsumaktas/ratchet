# Fix Modu — Hata Ezici

## Hedef
Lint, type ve test hatalarini sistematik olarak SIFIRA indirmek.

## Strateji

### 1. Haritalama
```bash
$LINT_CMD 2>&1 | sort | uniq -c | sort -rn > /tmp/lint-map.txt
$TYPE_CMD 2>&1 | sort > /tmp/type-map.txt
```
Hangi dosyada kac hata var? En cogundan basla.

### 2. Onceliklendirme
1. Build-breaking hatalar (KRITIK — bunlar olmadan hicbir sey calismaz)
2. Test failure'lar (fonksiyonel bozukluk)
3. Type hatalar (compile-time guvenlik)
4. Lint hatalari (kod kalitesi)

### 3. Tek Dosya, Tek Hata Turu
- Bir dosyadaki TUM lint hatalarini fix'le (ayni turden)
- FARKLI tur hatalari karistirma (lint + type ayni deneyde YASAK)
- Ornek: `file.ts`'deki 5 "no-unused-vars" → tek deney

### 4. Ratchet
- Hata sayisi azaldiysa → TUT
- Hata sayisi ayni → AT (degisiklik ise yaramadi)
- Hata sayisi arttiysa → AT

### 5. Durma
- Tum hedef metrikler sifir → BASARI, SUMMARY yaz
- Kalan hatalar fix edilemiyor (3 deneme basarisiz) → NOTES'a yaz, dur

## Anti-Pattern'lar
- `// @ts-ignore` veya `// eslint-disable` ile hata BASTIRMA — gercek fix yap
- Hatayi baska dosyaya TASIMA — cozmeden cikma
- "Bu hata onceden vardi" → ilgilenme, baska hataya gec (scope koruma)
