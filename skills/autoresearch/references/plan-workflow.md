# Plan Modu — Interaktif Wizard

## Amac
Belirsiz hedefi ("projeyi iyilestir") somut, olculebilir donmus metrige cevirir.
Config dosyasi olusturur, sonraki `run/fix/debug/security` cagrilari icin hazirlik yapar.

## Adimlar

### 1. Proje Tespit
- Otomatik: package.json, pyproject.toml, Cargo.toml, go.mod, Makefile oku
- Tech stack, test framework, lint tool tespit et

### 2. Kullaniciya Sor (AskUserQuestion)

**Soru 1: Mod**
"Ne yapmak istiyorsun?"
- Genel iyilestirme (run)
- Bug fix (debug)
- Hata temizligi (fix)
- Guvenlik taramasi (security)
- Sadece analiz (predict)

**Soru 2: Metrik**
"Basariyi neyle olcecegiz?"
- Test sayisi / coverage
- Lint hata sayisi
- Type hata sayisi
- Build suresi
- Bundle boyutu
- Custom komut

**Soru 3: Guard**
"Asla kirilmamasi gereken sey?"
- Testler (varsayilan)
- Build
- Custom komut
- Guard yok

**Soru 4: Boundary**
"Dokunulmamasi gereken dosyalar?"
- Varsayilanlar (lock, vendor, env)
- Ek glob pattern'lar

### 3. Config Olustur

Write `.autoresearch/config.json`:
```json
{
  "mode": "<secilen-mod>",
  "never_touch": ["*.lock", "..."],
  "guard_command": "<secilen-guard>",
  "parallel_workers": 1,
  "max_experiments": null,
  "frozen_commands": {
    "test": "<otomatik-tespit>",
    "lint": "<otomatik-tespit>",
    "type": "<otomatik-tespit>",
    "build": "<otomatik-tespit>"
  }
}
```

### 4. Baseline Al
Tum donmus metrikleri calistir, sonuclari goster.

### 5. Kullaniciya Onayla
"Config hazir. `/autoresearch <mod>` ile baslayabilirsin."
