# Photon Chat

**Telefon numarası yok. E-posta yok. Hesap yok. Sadece indir ve kullan.**

Photon Chat, kimliğinizi açığa çıkarmadan anlık mesajlaşmanızı sağlayan gizlilik odaklı bir mesajlaşma uygulamasıdır.

---

## İndir

| Platform | İndir |
|----------|-------|
| 📱 Android | [**APK İndir →**](../../releases/latest) |
| 🤖 Huawei | [**APK İndir →**](../../releases/latest) *(Google Play gerektirmez)* |
| 🌐 Windows | [**Windows İndir →**](../../releases/latest) |
| 🐧 Linux | [**Linux İndir →**](../../releases/latest) |
| 🍏 iOS | Yakında *(Apple Developer hesabı gerektirir)* |

> **Android / Huawei:** APK dosyasını indirip aç. "Bilinmeyen kaynaktan yükle" izni isteyebilir — izin ver ve devam et.  
> Huawei cihazlarda Google Play Services gerekmez. APK doğrudan yüklenir.

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
| Grup sohbeti — merkeziyetsiz | ✅ |
| Yazıyor göstergesi | ✅ |
| Mesaj teslim / okundu durumu (✓ / ✓✓ yeşil) | ✅ |
| Mesaj silme ve düzenleme | ✅ |
| Mesaja emoji tepkisi (👍❤️😂😮😢😡) | ✅ |
| Mesaj alıntılama (reply/quote) | ✅ |
| Profil fotoğrafı ve durum mesajı | ✅ |
| Son görülme zamanı | ✅ |
| QR kod ile arkadaş ekleme | ✅ |
| Kullanıcı engelleme | ✅ |
| Karanlık / Aydınlık tema | ✅ |
| Grup yöneticisi (sustur / at) | ✅ |
| Grup duyuruları (admin yayını) | ✅ |
| Grup anketleri | ✅ |
| Bildirimler — yeni mesaj, gruptan atılma, susturulma | ✅ Android + Huawei |
| Otomatik güncelleme (kullanıcı izniyle) | ✅ |
| Küfür filtresi | ✅ |
| Pulse AI asistanı | ✅ |

---

## Huawei Desteği

Photon Chat, Google Play Services **gerektirmez** ve Huawei cihazlarda sorunsuz çalışır.

| | Durum |
|---|---|
| Uygulama yükleme (APK) | ✅ Google Play'siz yüklenebilir |
| Mesajlaşma & gruplar | ✅ Tam destekli |
| Bildirimler (uygulama açıkken) | ✅ Destekleniyor |
| Bildirimler (arka planda) | ✅ Uygulama arka planda çalışırken destekleniyor |
| Bildirimler (uygulama kapalıyken) | ⚠️ Huawei'nin pil optimizasyonu engelleyebilir — "Pil optimizasyonuna izin ver" ayarını kapat |

> **İpucu (Huawei):** Ayarlar → Uygulama Yönetimi → Photon Chat → Pil → "Pil optimizasyonu yok" seç. Aksi hâlde sistem arka plan görevlerini kesebilir.

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

**Gereksinimler:** Flutter 3.24+, Dart ≥ 3.2, Node.js ≥ 18

```bash
# Flutter bağımlılıkları
flutter pub get

# Sunucuyu lokalde çalıştır
cd server && npm install && npm start

# Android APK (Huawei dahil)
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

## Sürüm Geçmişi

| Sürüm | Yenilikler |
|-------|------------|
| **v2.0.1** | Bildirimler (Android + Huawei), gruptan atılma / susturulma bildirimi |
| **v2.0.0** | Emoji tepkileri, mesaj alıntılama, titreşim, karanlık/aydınlık tema, grup duyuruları, grup anketleri |
| **v1.0.5** | Otomatik güncelleme |
| **v1.0.4** | Okundu bilgisi, mesaj silme/düzenleme, profil fotoğrafı, son görülme, durum mesajı, QR kod |

---

## Lisans

[LICENSE](LICENSE)
