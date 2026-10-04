# Photon Chat

**Telefon numarası yok. E-posta yok. Hesap yok. Sadece indir ve kullan.**

Photon Chat, kimliğinizi açığa çıkarmadan anlık mesajlaşmanızı sağlayan gizlilik odaklı bir mesajlaşma uygulamasıdır.

---

## İndir

| Platform | İndir |
|----------|-------|
| 📱 Android | [**APK İndir →**](../../releases/latest) |
| 🌐 Windows | [**Windows İndir →**](../../releases/latest) |
| 🐧 Linux | [**Linux İndir →**](../../releases/latest) |
| 🍏 iOS | Yakında *(Apple Developer hesabı gerektirir)* |

> **Android:** APK dosyasını indirip aç. “Bilinmeyen kaynaktan yükle” izni isteyebilir — izin ver ve devam et.

---

## Başlamak İçin

### 1 — Kendi Ücretsiz Sunucunu Kur *(1 kez, 5 dakika)*

Photon Chat merkezi bir sunucu kullanmaz. Her kullanıcı kendi ücretsi̇z sunucusunu çalıştırır.

1. [render.com](https://render.com) — ücretsiz hesap aç
2. **New → Web Service** → bu repoyu bağla
3. Root Directory: `server` | Plan: **Free** | Deploy bas
4. Birkaç dakika sonra sana `https://xxxx.onrender.com` adresi verilir — bunu kaydet

### 2 — Uygulamayı Aç

1. Uygulamayı aç — kısa bir rehber görürsün
2. Render URL’ini gir (`https://xxxx.onrender.com`)
3. Bir kullanıcı adı seç — kimliğin otomatik oluşturulur
4. 5 haneli kodun hazır (ör. `12345`) — arkadaşların seni sadece bu kodla ekler

Hepsi bu kadar. Artık mesajlaşabilirsin.

---

## Özellikler

| Özellik | |
|---------|--|
| Telefon / e-posta gerektirmez | ✅ |
| Birebir ve grup mesajlarında uçtan uca şifreleme (X25519 + AES-GCM) | ✅ |
| Sunucu tarafında kalıcı kayıt yok (RAM-only) | ✅ |
| Ekran görüntüsü engeli (Android) | ✅ |
| Grup sohbeti (grup sahibinin sunucusunda) | ✅ |
| Yazıyor göstergesi | ✅ |
| Mesaj teslim durumu (✓ / ✓✓) | ✅ |
| Kullanıcı engelleme | ✅ |
| Grup yöneticisi (sustur / at) | ✅ |
| Küfür filtresi | ✅ |
| Pulse AI asistanı | ✅ |

---

## Gizlilik

| Veri | Davranış |
|------|----------|
| Kimlik (FIP bloğu) | Yalnızca cihazda saklanır — sunucuya gönderilmez |
| Birebir mesajlar | Uçtan uca şifreli, sunucu RAM’inde, kalıcı kayıt yok |
| Grup mesajları | Uçtan uca şifreli; grup anahtarı üye çıkarılınca yenilenir |
| Kişi listesi | Yalnızca cihazda |
| Hesap silme | Tüm veriler anında imha edilir |

---

## Pulse AI *(Opsiyonel)*

Uygulamaya entegre yapay zeka asistanı. Aktifleştirmek için Render dashboard → Environment → `ANTHROPIC_API_KEY` ekle. Eklemezsen uygulama normal çalışır.

---

## Geliştiriciler İçin

<details>
<summary>Kaynağı derleme</summary>

**Gereksinimler:** Flutter 3.24+, Dart ≥ 3.5, Node.js ≥ 18.17

```bash
# Flutter bağımlılıkları
flutter pub get

# Sunucuyu lokalde çalıştır
cd server && npm install && npm start

# Testler (sunucu + uygulama)
cd server && npm test && cd ..
flutter analyze && flutter test

# Android APK
flutter build apk --release

# Windows
flutter config --enable-windows-desktop
flutter build windows --release

# Linux
flutter config --enable-linux-desktop
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter build linux --release
```

</details>

---

## Lisans

[LICENSE](LICENSE)
