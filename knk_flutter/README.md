# Photon Chat — FIP Tabanlı Mesajlaşma (Flutter)

Telefon numarası ya da e-posta gerektirmeyen, 5 haneli koda dayalı
arkadaşlık eşleştirmesi ve özel sohbet uygulaması.

Uygulama kullanıcıya gösterilen adıyla **Photon Chat**, iç kod adı
`photon_chat` (eski adı `knk_messenger`/KNK).

> **Gereksinim**: Flutter 3.24 veya üzeri (Dart SDK >= 3.2).

## Özellikler

### v2.0.1 (Son Sürüm)
- Yerel push bildirimleri (Android + Huawei — Google Play Services gerektirmez)
- Yeni mesaj bildirimi ("X size mesaj attı")
- Gruptan atılma bildirimi ("X sizi gruptan çıkardı")
- Susturulma bildirimi ("X sizi susturdu")
- Titreşim bildirimi (uygulama açıkken)

### v2.0.0
- Mesaja emoji tepkisi (👍❤️😂😮😢😡)
- Mesaj alıntılama / yanıtlama (reply/quote)
- Karanlık / Aydınlık tema geçişi
- Grup duyuruları (admin yayın banner'ı)
- Grup anketleri (admin oluşturur, üyeler oy verir)
- Otomatik güncelleme (kullanıcı izniyle, veriler korunur)

### v1.0.x
- FIP tabanlı kimlik sistemi (telefon numarası / e-posta gerektirmez)
- Uçtan uca şifreleme (X25519 + AES-GCM)
- Sunucu tarafında kalıcı kayıt yok (RAM-only)
- Birebir özel sohbet + grup sohbeti
- Yazıyor göstergesi
- Mesaj teslim / okundu durumu (✓ / ✓✓ yeşil)
- Mesaj silme ve düzenleme
- Profil fotoğrafı ve durum mesajı
- Son görülme zamanı
- QR kod ile arkadaş ekleme
- Kullanıcı engelleme
- Grup yöneticisi (sustur / at)
- Küfür filtresi
- Pulse AI asistanı
- Ekran görüntüsü engelleme (FLAG_SECURE)

## Huawei Desteği

Photon Chat, Google Play Services **gerektirmez**. `flutter_local_notifications`
kütüphanesi doğrudan Android API'lerini kullanır — HMS veya GMS bağımlılığı yoktur.
Huawei cihazlarda tüm özellikler (mesajlaşma, gruplar, bildirimler) sorunsuz çalışır.

> **İpucu:** Huawei cihazlarda Ayarlar → Uygulama Yönetimi → Photon Chat → Pil → "Pil optimizasyonu yok" seç. Aksi hâlde arka plan bildirimleri engellenebilir.

## Proje yapısı

```
lib/
├── main.dart                 # Giriş noktası
├── root_gate.dart            # Kimlik var mı? -> Onboarding veya Kişiler
├── onboarding_screen.dart    # FIP oluşturma + FipCard widget'ı
├── server_setup_screen.dart  # Sunucu URL girişi
├── guide_screen.dart         # Kullanım rehberi
├── fip.dart                  # FIP üretimi, hash, 5 haneli kod türetme
├── local_store.dart          # Cihaz içi depolama (kimlik, kişiler, mesajlar)
├── knk_api.dart              # Sunucu ile iletişim katmanı
├── e2e.dart                  # Uçtan uca şifreleme (X25519 + AES-GCM)
├── obfuscate.dart            # Mesaj obfuskasyonu
├── message_guard.dart        # Küfür filtresi
├── notification_service.dart # Yerel bildirimler (Android + Huawei)
├── update_checker.dart       # Otomatik güncelleme kontrolü
├── profanity_filter.dart     # Kelime filtreleme
├── theme.dart                # Renkler, stiller (karanlık/aydınlık)
├── app_keys.dart             # API anahtarları
└── screens/
    ├── contacts_screen.dart      # Kişiler listesi + senkronizasyon
    ├── add_contact_screen.dart   # Kod ile arkadaş ekleme
    ├── chat_screen.dart          # Özel sohbet (tepki, alıntı, düzenleme)
    ├── group_chat_screen.dart    # Grup sohbeti (anket, duyuru)
    ├── create_group_screen.dart  # Grup oluşturma
    ├── join_group_screen.dart    # Gruba katılma
    ├── settings_screen.dart      # FIP görüntüleme + hesap silme + tema
    ├── pulse_ai_screen.dart      # Pulse AI asistanı
    └── qr_scan_screen.dart       # QR kod tarama
```

## Tek kod tabanından beş platform

Bu proje **tek bir Dart kod tabanıdır**. Aynı `lib/` klasöründen
Android, Huawei, iOS, Windows ve Linux için ayrı paketler üretilir.

### Android + Huawei (.apk)

```bash
flutter pub get
flutter build apk --release
```
> Aynı APK hem Android hem Huawei cihazlarda çalışır. Google Play Services gerektirmez.

### iOS (.ipa)

```bash
flutter pub get
flutter build ipa --release
```
> macOS + Xcode gerektirir.

### Windows (.exe)

```bash
flutter config --enable-windows-desktop
flutter pub get
flutter pub run flutter_launcher_icons
flutter build windows --release
```

Çıktı: `build/windows/x64/runner/Release/` altında `photon_chat.exe`

### Linux

```bash
flutter config --enable-linux-desktop
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter pub get
flutter build linux --release
```

Çıktı: `build/linux/x64/release/bundle/`

## Uygulama ikonu

```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

## Backend (eşleştirme sunucusu)

```bash
cd server
npm install
npm start
```

Sunucu:
- Telefon numarası / e-posta istemez, saklamaz
- Sadece FIP + 5 haneli kod + görünen ad, şifreli mesaj kuyruklarını RAM'de tutar
- Kalıcı veritabanı yok
- `/deactivate` çağrıldığında tüm veriler anında imha edilir

## Sürüm Geçmişi

| Sürüm | Yenilikler |
|-------|------------|
| **v2.0.1** | Bildirimler (Android + Huawei) — yeni mesaj, gruptan atılma, susturulma, titreşim |
| **v2.0.0** | Emoji tepkileri, mesaj alıntılama, karanlık/aydınlık tema, grup duyuruları, grup anketleri, otomatik güncelleme |
| **v1.0.5** | Otomatik güncelleme sistemi |
| **v1.0.4** | Okundu bilgisi, mesaj silme/düzenleme, profil fotoğrafı, son görülme, durum mesajı, QR kod |
| **v1.0.3** | Grup sohbeti, kullanıcı engelleme, küfür filtresi |
| **v1.0.2** | Yazıyor göstergesi, mesaj teslim durumu |
| **v1.0.1** | Temel mesajlaşma, sunucu kurulumu |
| **v1.0.0** | İlk sürüm — FIP kimlik, uçtan uca şifreleme |
