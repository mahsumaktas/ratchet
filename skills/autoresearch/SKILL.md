---
description: "Otonom proje iyilestirme sistemi. Karpathy ratchet + paralel worktree + guard commands + validator subagent + state machine. Tetikleyiciler: 'autoresearch', 'projeyi gelistir', 'uyurken calis', 'otomatik iyilestir', 'analyze and improve', 'continuously improve'."
argument-hint: "[mod] [iterasyon-sayisi] — mod: run(default)|debug|fix|security|predict|plan"
---

# Autoresearch v2 — Otonom Proje Iyilestirme

Karpathy felsefesi: **Kontrol edemedigin seyi kucult, kucuk olani kontrol et ve buyut.**
Eklenen: paralel worktree, guard komutlar, validator subagent, state machine, git-as-memory.

Esinlenme: [uditgoenka/autoresearch](https://github.com/uditgoenka/autoresearch), [OpenAI Codex PLANS.md](https://developers.openai.com/cookbook/articles/codex_exec_plans), [barnum state machines](https://github.com/barnum-circus/barnum), [ralphy parallel worktrees](https://github.com/michaelshimeles/ralphy), [subagent-orchestration](https://skills.sh/dimitrigilbert/ai-skills/subagent-orchestration).

---

## Modlar

| Mod | Komut | Odak |
|-----|-------|------|
| **run** | `/autoresearch` veya `/autoresearch run` | Genel iyilestirme (varsayilan) |
| **debug** | `/autoresearch debug` | Bilimsel bug avlama — reproduce → izole → fix |
| **fix** | `/autoresearch fix` | Hata ezici — lint/type/test hatalari sifira kadar |
| **security** | `/autoresearch security` | OWASP/STRIDE guvenlik taramas → fix |
| **predict** | `/autoresearch predict` | Coklu-persona on-analiz (degisiklik yapmaz, oncelik listesi cikarir) |
| **plan** | `/autoresearch plan` | Interaktif wizard — belirsiz hedefi donmus metrige cevirir |

Iterasyon sayisi: `/autoresearch fix 20` → 20 deney yap. Bos = sonsuz.

---

## Temel Kurallar

1. **Bir deney = bir degisiklik.** Batch YASAK. Tek dosya, tek sorun, tek commit.
2. **Donmus metrik.** Bootstrap'ta tanimlanir, sonra ASLA degismez.
3. **Ratchet.** Iyilestiyse TUT, degilse AT. Tartisma yok.
4. **Guard komutu.** Ana metrik iyilesse bile guard KIRILIRSA → AT. (ornek: lint duzelirken test kirilmasi)
5. **Basitlik kriteri.** 20+ satir ekleme + kucuk iyilestirme = REDDET. Kod silme + ayni sonuc = TUT.
6. **Boundary kurallari.** `never_touch` glob'lari varsa o dosyalara DOKUNMA.
7. **Durma.** Kullanici durdurana kadar calis. "Devam edeyim mi?" diye SORMA.

---

## State Machine

Her deney su state'lerden gecer. Gecersiz gecis IMKANSIZ.

```
BOOTSTRAP → SELECT_TARGET → READ_FILE → MAKE_CHANGE → VALIDATE → DECIDE → COMMIT/REVERT → LOG → SELECT_TARGET...
                                                          ↑
                                                   (validator subagent)
```

State gecisleri:
- `BOOTSTRAP` → `SELECT_TARGET` (tek sefer, ilk deney)
- `SELECT_TARGET` → `READ_FILE`
- `READ_FILE` → `MAKE_CHANGE`
- `MAKE_CHANGE` → `VALIDATE`
- `VALIDATE` → `DECIDE`
- `DECIDE:keep` → `COMMIT` → `LOG` → `SELECT_TARGET`
- `DECIDE:discard` → `REVERT` → `LOG` → `SELECT_TARGET`
- `LOG` → `STOP` (durma kosulu saglanirsa)

---

## Faz 0 — Bootstrap (Tek Sefer)

### 0.1 Branch
```bash
git checkout -b autoresearch/$(date +%Y%m%d-%H%M%S)
```

### 0.2 Onceki State
Read `.autoresearch/state.json` — varsa kaldigin yerden devam et. (Context Reset Protokolu)

### 0.3 Proje Kesfet (Paralel Subagent)
3 Explore agent paralel:
1. Agent 1: Glob kaynak dosyalari + Read README + manifest
2. Agent 2: `git log --oneline -20` + `git diff --stat HEAD~10` + Grep `TODO|FIXME|HACK|BUG`
3. Agent 3: Test/lint/build komutlarini tespit et (package.json scripts, Makefile, pyproject.toml)

### 0.4 Boundary Kurallari
Eger projede `.autoresearch/config.json` varsa oku:
```json
{
  "never_touch": ["*.lock", "migrations/**", "vendor/**", ".env*"],
  "guard_command": "npm test",
  "parallel_workers": 3,
  "notify_webhook": "https://hooks.slack.com/...",
  "mode_overrides": {}
}
```
Yoksa varsayilan boundary'ler: `*.lock`, `node_modules/**`, `vendor/**`, `.env*`, `*.min.js`

### 0.5 Donmus Metrik + Guard Tanimla

**Ana metrikler** (frozen — DEGISTIRME):
```bash
TEST_CMD="npm test 2>&1"
LINT_CMD="npx eslint . --format compact 2>&1 | wc -l"
TYPE_CMD="npx tsc --noEmit 2>&1 | grep -c 'error TS'"
BUILD_CMD="npm run build 2>&1; echo $?"
```

**Guard komutu** (her zaman pass etmeli):
```bash
GUARD_CMD="npm test 2>&1"  # config'den gelir veya TEST_CMD ile ayni
```

Guard ≠ ana metrik. Ana metrik iyilesme olcer, guard regresyon engeller. Ornek: lint duzeltirken testler kirilmasin.

### 0.6 Git-as-Memory Baseline
```bash
git log --oneline -20  # son 20 commit → NOTES.md'ye yaz
git diff --stat HEAD~5  # son degisiklikler → baglamda tut
```

### 0.7 State + Checkpoint Olustur

Write `.autoresearch/state.json`:
```json
{
  "version": 2,
  "project": "<isim>",
  "branch": "autoresearch/<ts>",
  "mode": "<run|debug|fix|security>",
  "start": "<ISO>",
  "experiment": 0,
  "state": "SELECT_TARGET",
  "kept": 0,
  "discarded": 0,
  "consecutive_discards": 0,
  "strategy": "default",
  "baseline": { "tests": 42, "lint": 23, "types": 7, "build": true },
  "best": { "tests": 42, "lint": 23, "types": 7, "build": true },
  "frozen_commands": {
    "test": "<tam komut>",
    "lint": "<tam komut>",
    "type": "<tam komut>",
    "build": "<tam komut>",
    "guard": "<tam komut>"
  },
  "never_touch": ["*.lock", "migrations/**"],
  "failed_targets": {},
  "discoveries": []
}
```

Write `.autoresearch/results.tsv`:
```
exp	commit	tests	lint	types	build	guard	status	file	description	rationale
0	<hash>	42	23	7	ok	pass	baseline	-	degisiklik yok	-
```

Write `.autoresearch/CHECKPOINT.md` (Codex PLANS.md pattern):
```markdown
# Autoresearch Checkpoint

## Context & Orientation
<projenin ne oldugu, tech stack, mevcut durum — sifir bilgiyle okuyan birinin anlamasi icin>

## Progress
- [x] Bootstrap tamamlandi
- [ ] Deney 1...

## Decision Log
| # | Karar | Neden | Alternatif |
|---|-------|-------|------------|

## Surprises & Discoveries
<beklenmeyen bulgular — unused 500-satir modul, gizli dependency, vb.>

## Current Strategy
<hangi dosya grubuna, hangi sorun turune odaklaniliyor>
```

Write `.autoresearch/NOTES.md` — serbest format notlar.

---

## Ana Dongu

### Adim 1 — Git-as-Memory (Her Iterasyon Basi)
```bash
git log --oneline -5   # son yapilan deneyler
git diff --stat        # mevcut degisiklikler
```
Bu bilgiyi kullanarak ayni hataya dusme, onceki yakin-basarilari farkli aciyla dene.

### Adim 2 — Hedef Sec (state: SELECT_TARGET)

**Mod bazli oncelik:**

**run modu:**
1. P0: guvenlik acigi, bug, veri kaybi riski
2. En cok lint/type hatasi olan dosya
3. En karmasik dosya (uzun fonksiyon, derin nesting)
4. TODO/FIXME iceren dosya
5. Onceki yakin-basarili dosya

**debug modu:**
1. Kullanicinin raporladigi bug'un stack trace'indeki dosyalar
2. Error log'larda gecen dosyalar
3. Son degisen dosyalar (git log)

**fix modu:**
1. En cok hata iceren dosya (lint + type + test failure)
2. Hata sayisina gore sirala, en cogundan basla

**security modu:**
1. Input handling dosyalari (controller, route, handler)
2. Auth/session dosyalari
3. SQL/DB erisim dosyalari
4. Dosya islem dosyalari

**Boundary kontrolu:**
- `never_touch` glob'larina uyan dosyalar ATLA
- Ayni dosyada 3 ardisik discard → o dosyayi BIRAK, `failed_targets`'a ekle

### Adim 3 — Oku + Degistir (state: READ_FILE → MAKE_CHANGE)

1. **Read** ile hedef dosyayi tamamen oku
2. Tek bir iyilestirme belirle
3. **Edit** ile uygula (diff-first, bastan yazma YASAK)

**Yapilabilir:** bug fix, guvenlik acigi, error handling, dead code temizligi, type annotation, kod basitlestirme
**YAPMA:** calisan kodu yeniden yazma, public API degistirme, yeni dependency, comment ekleme

### Adim 4 — Dogrula (state: VALIDATE)

**4a. Donmus metrikler calistir:**
```bash
$TEST_CMD → test_result
$LINT_CMD → lint_result
$TYPE_CMD → type_result
$BUILD_CMD → build_result
$GUARD_CMD → guard_result  # MUST PASS
```

**4b. Validator Subagent (3+ dosya degistiginde veya her 5 deneyde bir):**
Ayri bir subagent calistir — degisikligi OKUYAN (sadece metrik calistirmayan) bir reviewer:
```
"Hedef dosyayi oku. Degisiklik: [diff]. Su sorulari cevapla:
1. Okunabilirlik iyilesti mi, kotuselti mi?
2. Gizli side-effect var mi?
3. Edge case kaciriliyor mu?
Verdict: APPROVE / FLAG"
```
FLAG gelirse → karar tablosunda ek bilgi olarak kullan (otomatik AT degil, ama agirlik verir).

### Adim 5 — Karar (state: DECIDE)

| Durum | Guard | Karar |
|-------|-------|-------|
| Metrik iyilesti | PASS | **TUT** |
| Metrik ayni, kod kisaldi | PASS | **TUT** |
| Metrik ayni, kod buyudu | PASS | **AT** |
| Metrik iyilesti | FAIL | **AT** (guard kirildi) |
| Metrik kotuselti | any | **AT** |
| Validator FLAG + metrik ayni | PASS | **AT** (kalite sorunu) |

### TUT (state: COMMIT):
```bash
git add <dosya>
git commit -m "autoresearch(exp-N): <ne yapildi>

metrik: lint 23→18, tests 42→42, guard: pass
satir: +3 -7 (net -4)
rationale: <neden bu hedef secildi>"
```
State: `best` guncelle, `consecutive_discards = 0`

### AT (state: REVERT):
```bash
git checkout -- <dosya>
```
NOTES.md'ye neden basarisiz, CHECKPOINT.md Decision Log'a ekle.
State: `consecutive_discards++`, `failed_targets` guncelle.

### Adim 6 — Log (state: LOG)

`results.tsv`'ye satir ekle. `state.json` guncelle. `CHECKPOINT.md` Progress guncelle.

**Discovery tespit:** deney sirasinda beklenmeyen bir sey bulduysan (unused modul, gizli bug, vb.) → `state.json` discoveries array'ine ekle + CHECKPOINT.md Surprises'a yaz. Bu discovery sonraki hedef seciminde oncelik kazanir.

---

## Strateji Degisimi

| Kosul | Aksiyon |
|-------|---------|
| 5 ardisik discard | Strateji degistir (bkz. asagi) |
| 10 ardisik discard | SUMMARY yaz, dur |
| Build kirildi + 2 denemede duzelmedi | ALERT.md yaz, dur |
| Tum lint/type sifir | Kutla, baska metrige gec veya dur |

**Strateji rotasyonu:**
1. `default` → `low-hanging-fruit` (en kolay fix'ler)
2. `low-hanging-fruit` → `deep-refactor` (karmasik dosyalar)
3. `deep-refactor` → `security-sweep` (guvenlik odakli)
4. `security-sweep` → `dead-code-cleanup` (temizlik)
5. `dead-code-cleanup` → `discovery-driven` (onceki surprises'lardan)

---

## Paralel Mod (Opsiyonel)

`parallel_workers > 1` ise veya `/autoresearch run --parallel` ile:

1. N adet FARKLI hedef dosya sec
2. Her biri icin ayri Agent calistir (worktree isolation DEGIL, ayni branch ama farkli dosyalar)
3. Her agent tek dosyayi degistirir + olcer
4. Sonuclar toplanir, TUT/AT kararlari verilir
5. TUT'lar commit edilir

**KURAL:** Paralel modda ayni dosyayi iki agent ASLA degistirmez. Dosya secimi mutex.

---

## Context Reset Protokolu

Context sifirlandi veya `/compact` yapildiysa:

1. Read `.autoresearch/state.json` → nerede kaldigin, hangi state
2. Read `.autoresearch/CHECKPOINT.md` → proje baglami + kararlar + surprises
3. Read `.autoresearch/results.tsv` → `tail -10` son deneyler
4. `git log --oneline -5` → son commitler
5. State machine'deki `state` field'indan devam et
6. **DURMA, SORMA, CALIS**

---

## Mod-Spesifik Davranislar

### debug modu
Referans: `references/debug-workflow.md`
- Reproduce → Minimize → Root cause → Fix → Regresyon testi
- Her bug icin "5 Whys" uygulanir
- Fix oncesi failing test YAZILIR, sonra fix yapilir (TDD)

### fix modu
Referans: `references/fix-workflow.md`
- Hedef: lint/type/test hata sayisini SIFIRA indirmek
- Durma kosulu: tum metrikler sifir veya iterasyon limiti
- En cok hata iceren dosyadan basla, azalan sirada

### security modu
Referans: `references/security-workflow.md`
- OWASP Top 10 + STRIDE taramasi
- Input validation, SQL injection, XSS, auth bypass, path traversal
- Her bulgu icin severity: CRITICAL / HIGH / MEDIUM / LOW
- CRITICAL → hemen fix, HIGH → fix denemesi, MEDIUM/LOW → NOTES'a yaz

### predict modu
Referans: `references/predict-workflow.md`
- Degisiklik YAPMAZ, sadece analiz
- 5 farkli persona (Performance Expert, Security Auditor, DX Advocate, Maintainability Purist, End User)
- Her persona en onemli 3 iyilestirmeyi oneriri
- Konsensus + oncelik listesi cikarir
- Cikti: `.autoresearch/PREDICTIONS.md`

### plan modu
Referans: `references/plan-workflow.md`
- Interaktif wizard: "Ne iyilestirmek istiyorsun?" → belirsiz hedegi donmus metrige cevirir
- AskUserQuestion ile mod, metrik, guard, boundary sorar
- Cikti: `.autoresearch/config.json` + hazir state

---

## Final Ozet

Tum deneyler bitince Write `.autoresearch/SUMMARY.md`:

```markdown
# Autoresearch v2 Ozeti

**Proje:** <isim> | **Mod:** <mod> | **Branch:** autoresearch/<ts>
**Sure:** <baslangic> → <bitis>

## Metrik Degisimi
| Metrik | Baslangic | Son | Degisim |
|--------|-----------|-----|---------|
| Test | 42 | 48 | +6 |
| Lint | 23 | 11 | -12 |
| Type | 7 | 3 | -4 |

## Istatistik
- Toplam deney: N | Tutulan: X (%Y) | Atilan: Z
- Strateji degisimi: K kez
- Validator FLAG: M kez

## En Etkili Degisiklikler
<top 5, commit hash + metrik degisimi>

## Surprises & Discoveries
<beklenmeyen bulgular>

## Atilip Ogrenilenler
<basarisiz denemelerden dersler>

## Kullanici Icin Kalan Isler
<buyuk, agent'in yapamayacagi isler>
```

---

## Neden v2 Daha Iyi

| Ozellik | v1 | v2 |
|---------|----|----|
| Guard komutu | Yok | Regresyon engeller |
| State machine | Serbest dongu | Gecersiz gecis imkansiz |
| Git-as-memory | Yok | Her iterasyon basi git log/diff okur |
| Validator | Yok | Ayri subagent kod OKUR |
| Paralel | Seri | N worker ayni anda |
| Context reset | state.json + NOTES | CHECKPOINT.md (self-contained) |
| Modlar | Tek | 6 mod (run/debug/fix/security/predict/plan) |
| Boundary | Yok | never_touch glob'lari |
| Strateji rotasyonu | 5 discard → dur | 5 discard → strateji degistir, 10 → dur |
| Decision log | Yok | Her karar neden + alternatif ile |
| Discovery tracking | Yok | Surprises → sonraki hedef onceligi |
