# Photon Chat

**Telefon numarası yok. E-posta yok. Sadece 5 haneli bir kod.**

Photon Chat, kimliğinizi açığa çıkarmadan anlık mesajlaşmanızı sağlayan, FIP (Fingerprint Identity Protocol) tabanlı gizlilik odaklı bir mesajlaşma uygulamasıdır. Flutter ile yazılmıştır; Android, iOS, Windows ve Linux'ta çalışır.

---

## Nasıl Çalışır?

1. Uygulamayı açın — otomatik olarak size özel bir **FIP** (kriptografik parmak izi) oluşturulur.
2. Bu FIP'ten türetilen **5 haneli kod** sizin adresinizdir. Paylaşın.
3. Karşı tarafın 5 haneli kodunu girerek arkadaş ekleyin.
4. Sunucu sadece şifrelenmiş/obfüske mesajları RAM'de tutar; kalıcı veritabanı yoktur.

---

## Özellikler

- Telefon numarası veya e-posta gerektirmez
- 5 haneli kodla arkadaş eşleştirmesi
- Sunucu tarafında kalıcı kayıt yok (RAM-only)
- Hesap silindiğinde tüm veriler anında yok edilir
- Çıkışta sohbet imha etme seçeneği
- Deaktif kullanıcı uyarısı (karşı taraf hesabı sildiyse bildirim)
- Android, iOS, Windows, Linux desteği (tek kod tabanı)

---

## Kurulum

### Gereksinimler

- Flutter 3.16 veya üzeri (`flutter --version` ile kontrol edin)
- Dart SDK >= 3.2
- Node.js >= 18 (sunucu için)

### Projeyi Aç

```bash
tar -xzf photon_chat_flutter.tar.gz
cd knk_flutter
```

### Flutter Bağımlılıklarını Yükle

```bash
flutter pub get
```

### Sunucuyu Başlat

```bash
cd server
npm install
npm start
```

Sunucu varsayılan olarak `http://localhost:3000` adresinde çalışır.  
`lib/knk_api.dart` içindeki `baseUrl` değerini kendi sunucu adresinizle güncelleyin.

---

## Derleme

### Android

```bash
flutter build apk --release         # APK (test / yan yükleme)
flutter build appbundle --release   # AAB (Play Store)
```

### iOS

```bash
flutter build ipa --release
```

> macOS + Xcode gerektirir.

### Windows

```bash
flutter config --enable-windows-desktop
flutter create .
flutter pub get
flutter build windows --release
```

Çıktı: `build/windows/x64/runner/Release/`

### Linux

```bash
flutter config --enable-linux-desktop
flutter create .
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter pub get
flutter build linux --release
```

Çıktı: `build/linux/x64/release/bundle/`

---

## Proje Yapısı

```
knk_flutter/
├── assets/icon/           # Uygulama ikonları
├── lib/
│   ├── main.dart          # Giriş noktası
│   ├── root_gate.dart     # Kimlik kontrolü → Onboarding veya Kişiler
│   ├── fip.dart           # FIP üretimi ve 5 haneli kod türetme
│   ├── knk_api.dart       # Sunucu iletişim katmanı
│   ├── local_store.dart   # Cihaz içi depolama
│   ├── obfuscate.dart     # Mesaj obfüskasyonu
│   ├── theme.dart         # Renkler ve stiller
│   ├── onboarding_screen.dart
│   └── screens/
│       ├── contacts_screen.dart
│       ├── add_contact_screen.dart
│       ├── chat_screen.dart
│       └── settings_screen.dart
└── server/
    ├── index.js           # Express röle sunucusu
    └── package.json
```

---

## Gizlilik Yaklaşımı

| Veri | Sunucu Davranışı |
|------|------------------|
| Kimlik | FIP hash'i — asıl anahtar cihazda kalır |
| Mesajlar | RAM'de obfüske blob, kalıcı kayıt yok |
| Kişi listesi | Cihazda (`shared_preferences`) |
| Hesap silme | `/deactivate` → ilgili tüm veriler anında silinir |

> **Not:** Mevcut `obfuscate.dart` görsel gizleme sağlar, kriptografik güvenlik sunmaz. Üretim ortamı için X25519 + AES-GCM tabanlı uçtan uca şifreleme önerilir.

---

## Lisans

[LICENSE](LICENSE) dosyasına bakın.
