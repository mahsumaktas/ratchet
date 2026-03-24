# Security Modu — Guvenlik Taramasi + Fix

## Metodoloji
OWASP Top 10 (2021) + STRIDE threat model.

## Tarama Siralamas

### 1. Input Handling (KRITIK)
- [ ] SQL Injection: raw query var mi? Parameterized query kullaniliyor mu?
- [ ] XSS: kullanici girdisi escape edilmeden DOM'a yaziliyor mu?
- [ ] Command Injection: user input shell komutuna gidiyor mu?
- [ ] Path Traversal: dosya islemlerinde `../` kontrolu var mi?
- [ ] SSRF: kullanici URL'si backend'den fetch ediliyor mu?

### 2. Auth & Session
- [ ] Hardcoded secret/API key var mi?
- [ ] JWT validation eksik mi?
- [ ] Session fixation riski var mi?
- [ ] Password plaintext saklanıyor mu?
- [ ] Rate limiting var mi?

### 3. Data Exposure
- [ ] Error mesajlari hassas bilgi sizdiriyor mu? (stack trace, DB schema)
- [ ] Log'larda PII (kisisel veri) var mi?
- [ ] API response'larda gereksiz field donuluyor mu?
- [ ] .env, credentials dosyasi repo'da mi?

### 4. Dependencies
- [ ] Bilinen CVE'li dependency var mi? (`npm audit` / `pip audit`)
- [ ] Outdated security-critical paketler var mi?

## Severity Seviyeleri
| Severity | Aksiyon | Ornek |
|----------|---------|-------|
| CRITICAL | Hemen fix, deney DURDUR | SQL injection, hardcoded secret |
| HIGH | Fix dene (3 deneme) | XSS, auth bypass |
| MEDIUM | NOTES'a yaz | Missing rate limit |
| LOW | NOTES'a yaz | Verbose error messages |

## Fix Kurallari
- CRITICAL bulunan fix edilemiyorsa → ALERT.md yaz, HEMEN DUR
- Guvenlik fix'i yapilirken yeni guvenlik acigi ACMA
- Her fix icin: "Bu hangi OWASP kategorisini kapatiyor?" dokumante et
- `never_touch` dosyalarina dokunma — sadece raporla
