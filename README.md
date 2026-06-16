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

> **Android:** APK dosyasını indirip aç. "Bilinmeyen kaynaktan yükle" izni isteyebilir — izin ver ve devam et.

---

## Başlamak İçin

### 1 — Kendi Ücretsiz Sunucunu Kur *(1 kez, 5 dakika)*

Photon Chat merkezi bir sunucu kullanmaz. Her kullanıcı kendi ücretsiz sunucusunu çalıştırır.

1. [render.com](https://render.com) — ücretsiz hesap aç
2. **New → Web Service** → bu repoyu bağla
3. Root Directory: `server` | Plan: **Free** | Deploy bas
4. Birkaç dakika sonra sana `https://xxxx.onrender.com` adresi verilir — bunu kaydet

### 2 — Uygulamayı Aç

1. Uygulamayı aç — kısa bir rehber görürsün
2. Render URL'ini gir (`https://xxxx.onrender.com`)
3. Bir kullanıcı adı seç — kimliğin otomatik oluşturulur
4. Adresin hazır → `12345@https://xxxx.onrender.com`

Hepsi bu kadar. Artık mesajlaşabilirsin.

---

## Özellikler

| Özellik | |
|---------|--|
| Telefon / e-posta gerektirmez | ✅ |
| Gerçek uçtan uca şifreleme (X25519 + AES-GCM) | ✅ |
| Sunucu tarafında kalıcı kayıt yok (RAM-only) | ✅ |
| Ekran görüntüsü engeli (Android) | ✅ |
| Grup sohbeti — 500–1000 kişi, merkeziyetsiz | ✅ |
| Yazıyor göstergesi | ✅ |
| Mesaj teslim durumu (✓ / ✓✓) | ✅ |
| Kullanıcı engelleme | ✅ |
| Grup yöneticisi (sustur / at) | ✅ |
| Küfür filtresi | ✅ |
| Pulse AI asistanı | ✅ |

---

## Gizlilik

| Veri | Davranış |
|------|----------|
| Kimlik | Cihazda şifreli — sunucuya gönderilmez |
| Mesajlar | Uçtan uca şifreli, RAM'de, kalıcı kayıt yok |
| Kişi listesi | Yalnızca cihazda |
| Hesap silme | Tüm veriler anında imha edilir |

---

## Pulse AI *(Opsiyonel)*

Uygulamaya entegre yapay zeka asistanı. Aktifleştirmek için Render dashboard → Environment → `ANTHROPIC_API_KEY` ekle. Eklemezsen uygulama normal çalışır.

---

## Geliştiriciler İçin

<details>
<summary>Kaynağı derleme</summary>

**Gereksinimler:** Flutter 3.16+, Dart ≥ 3.2, Node.js ≥ 18

```bash
flutter pub get
cd server && npm install && npm start
flutter build apk --release
```

</details>

---

## Lisans

[LICENSE](LICENSE)
