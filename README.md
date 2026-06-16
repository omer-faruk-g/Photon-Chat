# Photon Chat

**Telefon numarası yok. E-posta yok. Hesap yok. Sadece indir ve kullan.**

Photon Chat, kimliğinizi açığa çıkarmadan anlık mesajlaşmanızı sağlayan, FIP (Fingerprint Identity Protocol) tabanlı gizlilik odaklı bir mesajlaşma uygulamasıdır.

---

## Kullanıcı için: Nasıl Başlarsınım?

### Adım 1 — Kendi Sunucunu Kur (1 kez, 5 dakika)

Photon Chat merkezi bir sunucu kullanmaz. Her kullanıcı kendi ücretsi̇z sunucusunu çalıştırır.

1. [render.com](https://render.com) adresine git ve ücretsiz hesap aç
2. **New → Web Service** tıkla
3. Bu repoyu bağla: `https://github.com/omer-faruk-g/Photon-Chat`
4. **Root Directory** olarak `server` yaz
5. Plan: **Free** seç ve **Deploy** bas
6. Birkaç dakika sonra sana `https://xxxx.onrender.com` formatında bir URL verilir — bunu kaydet

> render.yaml dosyası sayesinde yapılandırma otomatiktir, hiçbir komut çalltırmana gerek yoktur.

### Adım 2 — Uygulamasını İndir

Android için APK'yı [Releases](../../releases) sayfasından indir ve yükle.

### Adım 3 — Aç, Kur, Kullan

1. Uygulamayı aç — kısa bir rehber görürsün
2. Render URL’ini gir (`https://xxxx.onrender.com`)
3. Bir kullanıcı adı seç — kimliğin otomatik oluşturulur
4. Adresin hazır: `12345@https://xxxx.onrender.com`

Hepsi bu kadar.

---

## Özellikler

| Özellik | Durum |
|---------|-------|
| Telefon / e-posta gerektirmez | ✅ |
| Gerçek uçtan uca şifreleme (X25519 + AES-GCM) | ✅ |
| Sunucu tarafında kalıcı kayıt yok (RAM-only) | ✅ |
| Ekran görüntüsü engeli (Android FLAG\_SECURE) | ✅ |
| Grup sohbeti (500–1000 kişi, merkeziyetsiz) | ✅ |
| Yazıyor göstergesi | ✅ |
| Mesaj teslim durumu (✓ / ✓✓) | ✅ |
| Kullanıcı engelleme | ✅ |
| Grup yöneticisi (sustur / at) | ✅ |
| Küfür filtresi | ✅ |
| Pulse AI asistanı | ✅ |
| Android, iOS, Windows, Linux | ✅ |

---

## Nasıl Çalışır?

1. Uygulama açılınca sana otomatik bir **FIP** (kriptografik parmak izi) oluşturulur
2. Bu FIP’ten türetilen **5 haneli kod** + kendi sunucu URL’in = senin adresin
3. Arkadaşlarına adresini ver: `KOD@https://sunucu.onrender.com`
4. Karşı tarafın adresini girerek arkadaş ekle
5. Mesajlar uçtan uca şifrelenir, sadece RAM’de tutulur

---

## Pulse AI

Uygulamaya entegre yapay zeka asistanı. Kelime anlamı, genel sorular, sohbet — şifreleme geçmeden kendi sunucun üzerinden çalışır.

Pulse AI’yi aktifleştirmek için Render dashboard’ından `ANTHROPIC_API_KEY` ortam değişkenini ekle. **Zorunlu değildir** — eklenmezse uygulama normal çalışmaya devam eder.

---

## Gizlilik

| Veri | Sunucu Davranışı |
|------|------------------|
| Kimlik | FIP hash’i — asıl anahtar cihazda kalr |
| Mesajlar | Uçtan uca şifreli, RAM’de şifreli blob, kalıcı kayıt yok |
| Kişi listesi | Cihazda (`shared_preferences`) |
| Hesap silme | `/deactivate` → ilgili tüm veriler anında silinir |

---

## Geliştiriciler için

<details>
<summary>Kaynağı derleme ve çalıştırma</summary>

### Gereksinimler
- Flutter 3.16+ (`flutter --version`)
- Dart SDK ≥ 3.2
- Node.js ≥ 18

### Kurulum

```bash
flutter pub get
```

### Sunucuyu Lokalde Çalıştır

```bash
cd server
npm install
npm start
```

### Android APK

```bash
flutter build apk --release
```

### Windows

```bash
flutter config --enable-windows-desktop
flutter build windows --release
```

### Linux

```bash
flutter config --enable-linux-desktop
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter build linux --release
```

</details>

---

## Lisans

[LICENSE](LICENSE) dosyasına bakın.
