#!/usr/bin/env python3
"""Generate release notes for a given tag and optionally update all releases via GitHub API."""

import os, sys, json, urllib.request, textwrap

CHANGELOGS = {
    'v1.0.0': (
        "### ✨ v1.0.0 Yenilikleri\n"
        "- 🔒 FIP tabanlı kimlik sistemi (telefon numarası veya hesap gerekmez)\n"
        "- 💬 Uçtan uca şifreli 1-1 mesajlaşma (X25519 + AES-GCM)\n"
        "- 👥 Kişi ekleme (5 haneli eşleşme kodu ile)\n"
        "- 🌗 Karanlık / Aydınlık tema\n"
        "- 🖥️ Android desteği"
    ),
    'v1.0.1': (
        "### ✨ v1.0.1 Yenilikleri\n"
        "- 🛠️ iOS ikon üretimi devre dışı bırakıldı (iOS klasörü henüz yok)\n"
        "- 🪲 Build sistemi hata düzeltmeleri"
    ),
    'v1.0.2': (
        "### ✨ v1.0.2 Yenilikleri\n"
        "- 🐧 Linux desteği eklendi\n"
        "- 🔁 Linux apt-get güvenilir yeniden deneme mekanizması\n"
        "- 🏗️ Build kararlılığı iyileştirmeleri"
    ),
    'v1.0.3': (
        "### ✨ v1.0.3 Yenilikleri\n"
        "- 🌐 Federe mimari: bridge sunucusu üzerinden kod→sunucu lookup\n"
        "- 🔗 Merkezi kayıt sistemi entegrasyonu"
    ),
    'v1.0.4+': (
        "### ✨ v1.0.4+ Yenilikleri\n"
        "- 🌐 Federe mimari: bridge sunucusu üzerinden kod→sunucu lookup\n"
        "- ⚡ Performans iyileştirmeleri ve hata düzeltmeleri\n"
        "- 🔧 Bağlantı kararlılığı artırıldı"
    ),
    'v1.0.5': (
        "### ✨ v1.0.5 Yenilikleri\n"
        "- 🐧 Linux desteği eklendi\n"
        "- 🏗️ Build sistemi iyileştirmeleri\n"
        "- 🪲 Küçük hata düzeltmeleri"
    ),
    'v2.0.0': (
        "### ✨ v2.0.0 Yenilikleri\n"
        "- 😀 Emoji reaksiyonlar (👍❤️😂😮😢😡)\n"
        "- 💬 Mesaj yanıtlama / alıntı\n"
        "- 📳 Yeni mesajda titreşim bildirimi\n"
        "- 🌓 Karanlık / Aydınlık tema değiştirici\n"
        "- 👥 Grup sohbetleri\n"
        "- 📢 Grup duyuruları (sadece yönetici)\n"
        "- 📊 Grup anketleri (yönetici oluşturur, üyeler oy kullanır)\n"
        "- 🔄 Otomatik güncelleme (kullanıcı izniyle, veriler korunur)"
    ),
    'v2.0.1': (
        "### ✨ v2.0.1 Yenilikleri\n"
        "- 📱 Huawei desteği (GMS gerektirmez, tüm Huawei cihazlarda çalışır)\n"
        "- 📄 Kapsamlı döküman güncellemeleri"
    ),
    'v2.0.2': (
        "### ✨ v2.0.2 Yenilikleri\n"
        "- 🌍 45 dil desteği (Google Translate ile gerçek zamanlı çeviri)\n"
        "- 🔤 Mesaj çevirisi (uzun bas → Çevir)\n"
        "- 🖼️ Sohbet duvar kağıdı seçimi\n"
        "- 📥 Çevrimdışı mesaj kuyruğu (internet gelince otomatik gönderir)\n"
        "- 🚫 Geliştirilmiş küfür filtresi (tüm 45 dili destekler)"
    ),
    'v2.0.3': (
        "### ✨ v2.0.3 Yenilikleri\n"
        "- ⏳ Kaybolan mesajlar (10s / 30s / 1dk / 5dk / 1 saat seçenekleri)\n"
        "- 📌 Mesaj sabitleme (uzun bas → Sabitle)\n"
        "- 🟢 Çevrimiçi / son görülme durumu\n"
        "- 🔗 Grup davet linki (kopyala & paylaş)\n"
        "- 🖼️ Profil fotoğrafı gösterimi (kişi listesi ve mesaj balonları)"
    ),
    'v2.0.4': (
        "### ✨ v2.0.4 Yenilikleri\n"
        "- 🪟 Windows yükleyici (.exe) — masaüstü kısayolu otomatik oluşturulur\n"
        "- 📷 QR kod ile kişi eşleştirme — kendi QR'ını göster, arkadaşının QR'ını tara\n"
        "- 🔗 Gruba 7 haneli kod veya davet linki ile katılma (photon:// formatı)\n"
        "- ✅ Kendi gönderdiğin mesajlar artık anında görünüyor\n"
        "- 🐛 Hata düzeltmeleri ve kararlılık iyileştirmeleri"
    ),
    'v2.0.5': (
        "### ✨ v2.0.5 Yenilikleri\n"
        "- 🎨 Ana ekran yeniden tasarlandı — profil şeridi, belirgin bölüm başlıkları\n"
        "- 👤 Profil şeridi: avatar, isim, durum mesajı ve kodun tek bakışta görünür\n"
        "- 📋 5 haneli koduna tıklayarak kopyala\n"
        "- 🖼️ Avatar portre fotoğraflarda artık yüz/üst bölge düzgün görünüyor\n"
        "- ➕ Alt bar: 'Kişi Ekle' ve 'Grup' yan yana iki düğme\n"
        "- 📝 Grup açıklaması — grup oluştururken kısa tanım yaz"
    ),
    'v3.0.0': (
        "### ✨ v3.0.0 Yenilikleri\n"
        "- 📸 Fotoğraf paylaşımı — galeriden görsel seç, sohbette gönder\n"
        "- 🔒 Gelen görseller varsayılan olarak bulanık — dokunarak aç\n"
        "- ⛔ Hassas/+18 içerik işaretleme — gönderen işaretlerse karşı tarafta siyah blok + uyarı mesajı\n"
        "- 🎙️ Sesli yazım (STT) — konuşarak mesaj yaz, 'Gönder' diyince otomatik gönderir\n"
        "- 🔇 STT varsayılan kapalı — Ayarlar → Sesli Mesaj'dan aktif edilir, mikrofon izni ister\n"
        "- ✏️ Mesaj düzenleme — uzun bas → Düzenle\n"
        "- 🗑️ Herkesten sil — uzun bas → Sil"
    ),
    'v3.0.1': (
        "### ✨ v3.0.1 Yenilikleri\n"
        "- 🔧 Başlangıç rehberi güncellendi — 5 haneli kod sistemi doğru anlatılıyor\n"
        "- 💾 Sunucu adresi artık kaydediliyor — uygulama her açılışında tekrar sorulmaz\n"
        "- 🎯 Kimlik oluşturulunca kod büyük ve belirgin gösteriliyor"
    ),
    'v3.0.2': (
        "### ✨ v3.0.2 Yenilikleri\n"
        "- 🔄 Arka plan keep-alive — uygulama kapalıyken de sunucu uyanık kalır (Android)\n"
        "- ⏰ Her 15 dakikada bir otomatik ping — Render ücretsiz sunucu uyumaz\n"
        "- 🌐 Uygulama açıkken her 10 dakikada ping (tüm platformlar)"
    ),
    'v3.0.3': (
        "### ✨ v3.0.3 Yenilikleri\n"
        "- 🎬 GIF oluşturucu — galeriden kare seç, animasyonlu GIF oluştur ve gönder\n"
        "- 🔍 Otomatik içerik taraması — GIF kareleri ve fotoğraflar gönderilmeden taranır\n"
        "- 🛡️ Avatar NSFW filtresi — uygunsuz profil fotoğrafı ayarlanamaz\n"
        "- ⛔ Küfür + görsel filtresi aynı anda çalışır — uygunsuz içerik hiç oluşturulmaz"
    ),
    'v3.0.4': (
        "### ✨ v3.0.4 Yenilikleri\n"
        "- 📊 Anket sistemi — istediğin kadar seçenek ekle/kaldır\n"
        "- ➕ Dinamik seçenek ekleme — anket oluştururken sınırsız seçenek"
    ),
    'v3.0.5': (
        "### ✨ v3.0.5 Yenilikleri\n"
        "- 🏷️ Uygulama adı Photon Chat olarak güncellendi — tüm KNK referansları kaldırıldı\n"
        "- 🎨 Tüm sınıf ve tema isimleri Photon adıyla yeniden düzenlendi"
    ),
    'v4.0.0': (
        "### 🚀 v4.0.0 Yenilikleri\n"
        "- 🎤 Sesli mesaj — bas-konuş, erkek/kadın TTS sesiyle gönderilir (gerçek ses korunmaz)\n"
        "- 📍 Konum paylaşımı — anlık konumunu sohbete gönder, OpenStreetMap'te aç\n"
        "- 📝 Bio — profile max 100 karakterlik kısa tanıtım ekle\n"
        "- 🎙 Ses cinsiyeti ayarı — Erkek veya Kadın sesi seç (Ayarlar'dan)"
    ),
    'v5.0.0': (
        "### 🚀 v5.0.0 Yenilikleri\n"
        "- 📱 Cihazlar arası hesap eşleştirme — aynı servera ikinci cihazdan bağlan\n"
        "- 🔑 9/12/15 haneli doğrulama kodu sistemi (3 deneme hakkı)\n"
        "- 👁️ Yan cihaz izleme — ana cihazdan tüm aktiviteleri gör\n"
        "- 🚫 Cihaz atma — atılan cihaz bir daha servera bağlanamaz (kalıcı ban)\n"
        "- 🕵️ FAKE tespit — yanlış kod girenleri otomatik FAKE olarak işaretle\n"
        "- 🛡️ FAKE yönetimi — fake hesapları izle, banla veya MOD yetkisi ver\n"
        "- 🔒 Protokol seviyesinde koruma — banlanan cihaz aynı servera asla erişemez"
    ),
    'v6.0.0': (
        "### 🚀 v6.0.0 Yenilikleri\n"
        "- 📎 Dosya paylaşımı — PDF, ZIP, DOC ve daha fazlası (maks 50 MB)\n"
        "- 🛡️ Grup moderatör rolü — MOD yetki ver/al, moderatörler mesaj silebilir\n"
        "- 📖 Hikayeler / Durum — 24 saat sonra kaybolan metin ve görsel hikayeler\n"
        "- ⭐ Mesaj yıldızlama — önemli mesajları kaydet ve sonra kolayca bul\n"
        "- 🔔 Bildirim sesi özelleştirme — cihaz kütüphanesinden ses seç ve önizle\n"
        "- 🔠 Yazı tipi boyutu ayarı — küçük / orta / büyük\n"
        "- 📤 Sohbet dışa aktarma — konuşmayı .txt olarak paylaş\n"
        "- ⚡ Hızlı yanıtlar — önceden kayıtlı mesaj şablonları\n"
        "- 🔐 Uygulama kilidi — PIN veya desen ile koruma (opsiyonel)"
    ),
    'v6.2.0': (
        "### 🔧 v6.2.0 — Büyük Kararlılık ve Hata Düzeltme Sürümü\n\n"
        "**Grup sohbetleri tamamen yeniden yazıldı:**\n"
        "- 🐛 Anket oluşturulunca gönderene görünmüyordu — düzeltildi\n"
        "- 🐛 Duyuru gönderilince gönderene görünmüyordu — düzeltildi\n"
        "- 🐛 Grup mesajları bazı üyelere ulaşmıyordu — hepsi sahibin sunucusuna gidiyor\n"
        "- 🐛 MOD atama/geri alma yeniden başlatınca kayboluyordu — kalıcı hale getirildi\n"
        "- 🐛 Üye atma yeniden başlatınca geri geliyordu — kalıcı hale getirildi\n\n"
        "**Sohbet ekranı düzeltmeleri:**\n"
        "- 🐛 \"…yazıyor\" göstergesi hiç görünmüyordu — düzeltildi\n"
        "- 🐛 Dosya baloncuğuna tıklayınca hiçbir şey olmuyordu — artık dosya açılıyor/paylaşılıyor\n"
        "- 🐛 Hızlı yanıt chip'i mesajı sessizce gönderiyordu — artık input'a ekliyor\n"
        "- 🐛 NSFW uyarısı gönderende görünmüyordu — düzeltildi\n"
        "- 🐛 Sohbet menüsünde çift \"Yıldızla\" öğesi vardı — temizlendi\n"
        "- 🐛 Yanıt/duyuru banner'ları null mesajlarda crash oluyordu — güvenli hale getirildi\n"
        "- 🐛 Chat girişinde çift dosya butonu vardı — kaldırıldı\n\n"
        "**Kurulum & tema:**\n"
        "- 🐛 Onboarding'de 5 haneli kod hiç gösterilmiyordu — artık \"Devam →\" butonuyla gösteriliyor\n"
        "- 🐛 Onboarding FIP satırları light modda görünmüyordu — düzeltildi\n"
        "- 🐛 Ayarlar tehlike kartı light modda karanlık leke oluyordu — tema-uyumlu hale getirildi\n"
        "- 🐛 Uygulama kilidi 5-6 haneli PIN kabul etmiyordu — düzeltildi\n"
        "- 🐛 Sesli mesaj bırakınca durmuyordu — düzeltildi\n\n"
        "**Diğer:**\n"
        "- 📖 Render.com sunucu kurulum adımları README ve rehber ekranında ayrıntılandırıldı\n"
        "- 🎨 Kişilerde çift hikaye çubuğu kaldırıldı\n"
        "- 👤 Kişi bio'su artık profilden çekiliyor"
    ),
    'v8.1.0': (
        "### 🌐 v8.1.0 — i18n Genişletmesi Tamamlandı\n\n"
        "Ayarlardan dil seçtiğinde neredeyse tüm ekranlar hedef dile çevriliyor:\n\n"
        "- ✅ Onboarding, Rehber, Sunucu Kurulumu\n"
        "- ✅ Kişiler, Kişi Ekle, Grup Oluştur, Gruba Katıl\n"
        "- ✅ Ayarlar (tümü), Yıldızlı Mesajlar\n"
        "- ✅ Grup Chat, Hikayeler, Cihazlar, Cihaz Eşleştirme\n"
        "- ✅ Uygulama Kilidi, Duvar Kağıdı\n\n"
        "**Toplam:** ~455 çeviri anahtarı, 45 dil.\n\n"
        "Bazı derin dialog metinleri (nadir kullanılanlar) hala Türkçe kalabilir — bir sonraki sürümde tamamlanacak."
    ),
    'v9.0.0': (
        "### 🎉 v9.0.0 — Grup QR Kodu + Bridge Auto-Lookup\n\n"
        "**Küçük bir özür:** v8.2.0 ve v8.3.0 build hataları nedeniyle yayınlanamadı. "
        "İçerikleri bu sürümde toplu olarak sunuluyor. Kusura bakma 🙏\n\n"
        "---\n\n"
        "**📱 Grup davet QR kodu:**\n"
        "- Grup sahibi menüden \"Davet Linki\" seçince artık büyük QR kod görünüyor\n"
        "- Karşı taraf kamerayla tarayınca her şey otomatik doldurulur\n\n"
        "**🎯 Gruba QR ile katılma:**\n"
        "- Gruba Katıl ekranında sağ üstte QR butonu\n"
        "- Tara → server URL otomatik dolar → istek gönderilir\n\n"
        "**🔗 Sadece 7 haneli kod yeter:**\n"
        "- Grup oluşturulunca kod otomatik bridge'e kayıt olur (photon-chat.onrender.com)\n"
        "- Gruba katılırken sunucu URL'i girmene gerek yok — bridge'den otomatik çekilir\n"
        "- Contacts açıkken grup kodları her 5 saniyede bir bridge'e yenilenir (server snapshot restart'ından sonra da erişilebilir kalır)\n\n"
        "**🎛️ QR scan iyileştirmeleri:**\n"
        "- Dual-mode: kişi (5 hane) vs grup (photon:// URI) — geçersiz QR reddedilir\n"
        "- Kamera ekranı ortasında hedefleme kutusu\n\n"
        "**🐛 Build fixler:**\n"
        "- v8.2/v8.3'te const wrapper etrafında runtime metod çağrısı hataları düzeltildi"
    ),
    'v8.3.0': (
        "### 🎯 v8.3.0 — Sadece Grup Kodu Yeter (Bridge Lookup)\n\n"
        "Artık gruba katılmak için sunucu URL'i girmene gerek yok.\n\n"
        "- ✨ Grup oluşturulunca kod otomatik bridge'e kayıt olur\n"
        "- ✨ Gruba katılırken 7 haneli kod yeter — server URL bridge'den otomatik çekilir\n"
        "- ✨ Contacts açıkken grup kodları her 5 saniyede bir bridge'e yenilenir (server snapshot geri yüklemesi için)\n"
        "- 🔧 Server URL alanı artık opsiyonel (ileri seviye)"
    ),
    'v8.2.0': (
        "### 📱 v8.2.0 — Grup Davet QR'ı + QR Scan İyileştirmeleri\n\n"
        "- ✨ **Grup davet QR'ı** — Grup sahibi menüden \"Davet Linki\" seçince artık büyük QR kod görünüyor\n"
        "- ✨ **Gruba QR ile katılma** — Gruba Katıl ekranında sağ üst QR butonu. Tara → server URL otomatik dolar → istek gönderilir\n"
        "- 🔧 QR tarama artık iki modda: kişi (5 hane) veya grup (photon://... URI)\n"
        "- 🔧 QR ekranı ortasında hedefleme kutusu\n"
        "- 🌐 QR ekranı ve grup davet bölümü tamamen çevirili"
    ),
    'v8.0.0': (
        "### 🌐 v8.0.0 — Çoklu Dil Desteği Genişletildi\n\n"
        "Ayarlardan dil seçiminde artık çok daha fazla ekran hedef dile çevriliyor:\n\n"
        "**Bu sürümde çevrilen ekranlar:**\n"
        "- ✅ Kişiler ana ekranı\n"
        "- ✅ Ayarlar (tümü)\n"
        "- ✅ Kişi Ekle\n"
        "- ✅ Grup Oluştur\n"
        "- ✅ Gruba Katıl\n"
        "- ✅ Yıldızlı Mesajlar\n"
        "- ✅ Sunucu Kurulumu\n\n"
        "**Sonraki sürüme kalan (v8.1.0):**\n"
        "- Chat ekranı, Grup Chat, Onboarding, Rehber, Hikayeler, Cihazlar, Kilit\n\n"
        "**Toplam:** 360+ çeviri anahtarı, 45 dil destekleniyor (Google Translate ile otomatik).\n\n"
        "Not: Mesaj çeviri özelliği (uzun bas → Çevir) her zaman tüm dilleri destekliyordu — bu güncelleme UI dili."
    ),
    'v7.2.1': (
        "### 🚨 v7.2.1 — Hotfix: Client actor field'ı eksikti\n\n"
        "**KRİTİK:** v7.2.0'da server auth için `actor` field'ı eklendi ama client hiçbir yerde göndermiyor du → kick/mute/edit/delete tümü 403 alıyordu.\n\n"
        "- 🔧 editMessage/deleteMessage → `actor: identity.fipId`\n"
        "- 🔧 muteGroupMember/unmuteGroupMember → `actor`\n"
        "- 🔧 leaveGroup → `actor`\n"
        "- 🔧 3 hard cast crash düzeltildi (offline_queue ts, group reject fromFipId, starred msgId)"
    ),
    'v7.2.0': (
        "### 🏛️ v7.2.0 — Server Refactor: Auth + Persistence + Performance\n\n"
        "**Persistence eklendi (BÜYÜK):**\n"
        "- 💾 Server 30 saniyede bir tüm state'i diske yazıyor\n"
        "- 🔁 Restart/redeploy sonrası tüm mesaj/grup/hikaye/kimlik geri yükleniyor\n\n"
        "**Güvenlik:**\n"
        "- 🛡️ Helmet + CORS + compression + rate limit (300 req/dk global)\n"
        "- 🛡️ AI endpoint stricter limit: 20/saat\n"
        "- 🛡️ Owner-auth: kick/mute/unmute/mesaj-düzenle/mesaj-sil için `actor` fipId doğrulaması\n"
        "- 🛡️ Global body limit 60MB → 256KB (büyük payload sadece medya endpoint'lerinde)\n"
        "- 🛡️ Per-field caps: avatar 300KB, chat text 8KB\n"
        "- 🛡️ /deactivate substring bug → düzeltildi (parçalara ayırıp eşleştiriyor)\n\n"
        "**Performans:**\n"
        "- ⚡ /lookup/:code artık O(1) reverse index ile\n"
        "- ⚡ /groups/by-code/:code artık O(1) index ile\n"
        "- ⚡ Compression middleware\n\n"
        "**Client-server alignment:**\n"
        "- 🔗 registerPresence artık E2E public key gönderiyor\n"
        "- 🔗 /profile response'unda public key var\n"
        "- 🔗 Friend request bio artık saklanıyor\n"
        "- 🔗 sendTyping receiverServerUrl'e gidiyor (myServerUrl değil)\n"
        "- 🔗 Notification dedupe (aynı ts reddediliyor)\n"
        "- 🔗 DELETE /notifs/:fipId/:ts endpoint eklendi\n\n"
        "⚠️ Server'ı Render'da mutlaka yeniden deploy et — npm install yapacak (helmet, cors, compression, express-rate-limit)."
    ),
    'v7.1.0': (
        "### 🎯 v7.1.0 — 7 Ajan Denetim Sonucu 100+ Bug Fix\n\n"
        "**Kritik güvenlik & gizlilik:**\n"
        "- 🔐 E2E keypair'i main.dart'ta hiç başlatılmıyordu — eklendi\n"
        "- 🔐 E2E keypair'i knk_ prefix'siz saklanıyordu, hesabı sil sonrası kalıyordu — knk_ prefix + migrasyon\n"
        "- 🛡️ Server /notifs GET destructive'ti — 2. cihaz bildirimleri kaybediyordu, artık non-destructive\n"
        "- 🛡️ Server /deactivate iteration-mutation bug — düzeltildi\n"
        "- 🛡️ Server device-link attempts field splice sonrası yanlış — düzeltildi\n\n"
        "**Grup sohbeti:**\n"
        "- Anket/duyuru/mute polling try/catch\n"
        "- Anket oyu optimistic + pendingVote (msgId boşken 404 önleme)\n"
        "- accept/reject/mute/kick optimistic + revert\n"
        "- Announcement ts safe cast\n"
        "- Input wallpaper okunabilirliği (Container color)\n\n"
        "**1-1 sohbet:**\n"
        "- Görsel/GIF/dosya/forward E2E encryption\n"
        "- edit/delete/reaction try/catch + optimistic\n"
        "- Encryption failure abort + toast (plaintext leak önleme)\n"
        "- Timer sızıntıları düzeltildi\n"
        "- Disappearing msg mounted check\n"
        "- Contact 60-char isim overflow fix\n"
        "- AppBar title ellipsis\n\n"
        "**Ayarlar/Onboarding:**\n"
        "- FipCard preview code artık gerçek kimliğe kaydediliyor (createIdentity accepts existing)\n"
        "- add_contact & create_group SingleChildScrollView\n"
        "- Onboarding FIP ListView physics fix\n"
        "- SetLock PIN dot count dinamik\n\n"
        "**UI/UX:**\n"
        "- QR scan SafeArea\n"
        "- Contacts alt bar 100+safeBottom padding\n"
        "- Device approve dialog FittedBox\n"
        "- Pulse AI input keyboard-aware\n"
        "- Story image NSFW scan + boyut kontrolü\n"
        "- GIF creator ilk kare fix + spinner color\n"
        "- Device link hint görünürlük\n\n"
        "⚠️ Server'ı Render'da tekrar deploy et — güvenlik fixleri için."
    ),
    'v7.0.0': (
        "### 🚨 v7.0.0 — Server Endpoint'leri + Kritik Fixler\n\n"
        "**Denetim büyük eksikleri ortaya çıkardı — server tarafında:**\n"
        "- 🔴 Hikayeler cross-user görünmüyordu (`/stories/*` endpoint'i eksikti) — eklendi\n"
        "- 🔴 Cihaz eşleştirme (v5.0.0) hiç çalışmıyordu (`/device-link/*` yok) — eklendi\n"
        "- 🔴 FAKE tespit (v5.0.0) tetiklenemiyordu — 3 yanlış kod otomatik FAKE + ban\n"
        "- 🔴 50MB dosya paylaşımı imkansızdı (server 2MB body limit) — 60MB'a çıkarıldı\n"
        "- 🔴 Bio (v4.0.0) sunucuda saklanmıyordu — presence + profile'a eklendi\n\n"
        "**Uygulama:**\n"
        "- 🔐 Görsel/GIF caption E2E şifrelenmiyordu — düzeltildi\n"
        "- 🛡️ Story yükleme hard cast crash — güvenli\n\n"
        "⚠️ Server'ı Render'da yeniden deploy etmen lazım — yeni endpoint'ler için."
    ),
    'v6.6.0': (
        "### 🔐 v6.6.0 — E2E Şifreleme + Kararlılık\n\n"
        "- 🔐 **KRİTİK GÜVENLİK:** Görsel/GIF gönderirken caption metni E2E şifrelenmiyordu — plaintext olarak sunucuya gidiyordu. Düzeltildi.\n"
        "- 🛡️ Hikaye yükleme hard cast crash — güvenli tip dönüşümü\n"
        "- 🛡️ Grup davet linki hard cast crash — güvenli tip dönüşümü"
    ),
    'v6.5.0': (
        "### 🛠️ v6.5.0 — Kararlılık + UI\n\n"
        "- 🔴 Chat/group poll loop crash → tüm mesaj güncellemesi duruyordu; try/catch + safe int cast\n"
        "- 🔴 Cihaz istekleri kartında \"Reddet (FAKE)\" butonu dar telefonda taşıyordu — Expanded\n"
        "- 🟠 Uygulama kilidi PIN göstergesi hep 6 nokta gösteriyordu — gerçek PIN uzunluğuna göre\n"
        "- 🟠 Kontaklar ana ekranda 5 haneli kodun sağ tarafı kesiliyordu — leadingWidth 88\n"
        "- 🟠 Ana ekranda alt bar (Kişi Ekle / Grup) telefon jest çubuğu altına giriyordu — SafeArea inset\n"
        "- 🟠 Hikaye görüntüleyicide başlık progress bar üzerine biniyordu — düzeltildi\n"
        "- 🎨 Türkçe diakritik düzeltmeleri: \"Yıldızlı Mesajlar\", \"Görsel Hikaye\", \"Sohbet Duvar Kâğıdı\", \"CİHAZ SESLERİ\", \"ARKADAŞININ 5 HANELİ KODU\""
    ),
    'v6.4.0': (
        "### 🛡️ v6.4.0 — 5 Ajan Paralel Denetim (25+ Bug Fix)\n\n"
        "**Grup sohbeti:**\n"
        "- 🐛 Anket oyu 2sn sonra kayboluyordu — merge logic düzeltildi\n"
        "- 🐛 Grup açılırken mesajlar 2sn boş geliyordu — anlık yükleme\n"
        "- 🐛 Üye katılma isteği kabul/red anlık yansımıyordu — düzeltildi\n"
        "- 🐛 Ekrandan çıkılınca toast crash olabiliyordu — güvenli\n\n"
        "**1-1 sohbet:**\n"
        "- 🐛 Mesaj düzenleme E2E şifrelemeyi bozuyordu — düzeltildi\n"
        "- 🐛 Otomatik scroll kullanıcının okumasını engelliyor — yeni mesajda scroll\n"
        "- 🐛 STT ve sesli mesaj birbirini bozuyordu — mutual exclusion\n"
        "- 🐛 Okundu göstergesi timer sızıntısı — düzeltildi\n\n"
        "**Ayarlar/Onboarding:**\n"
        "- 🐛 Bildirim sesi önizlemesi kapatınca durmuyordu — güvenli durdurma\n"
        "- 🐛 Sunucu URL doğrulama yoktu — http/https + host kontrolü\n"
        "- 🐛 Kimlik oluştururken hata handling yoktu — try/catch + spinner\n"
        "- 🐛 Rehberde son sayfada çift buton vardı — kaldırıldı\n"
        "- 🐛 TextEditingController sızıntıları — dispose eklendi\n\n"
        "**Uygulama kilidi:**\n"
        "- 🐛 3 yanlış PIN sonrası lockout yoktu — 30sn kilit (2x katlanan)\n\n"
        "**Duvar kağıdı:**\n"
        "- 🐛 Önizleme metni gerçek duvar kağıdının üstüne biniyordu — düzeltildi\n\n"
        "**Kişiler & hikayeler:**\n"
        "- 🐛 Yıldızlı mesajlar açılırken boş mesaj gösteriyordu — spinner\n"
        "- 🐛 Kişi ekle ağ hatası sessizce takılıyordu — hata bildirimi\n"
        "- 🐛 Hikaye viewer başlangıç indeksini yok sayıyordu — düzeltildi\n\n"
        "**Bildirimler:**\n"
        "- 🐛 Aynı bildirim 10sn'de bir tekrarlanıyordu — 30sn dedupe\n\n"
        "**Gizlilik:**\n"
        "- 🔐 Hesabı sil artık TÜM veriyi (PIN, wallpaper, bio, avatar, vs.) siliyor\n"
        "- 🔐 Yeni kullanıcı öncekinin ayarlarını miras almıyor artık"
    ),
    'v6.3.0': (
        "### 🎯 v6.3.0 — Anket, Yazı Boyutu ve Kararlılık\n\n"
        "**Kritik düzeltmeler:**\n"
        "- 🐛 Anket oluşturunca 1-2 saniye sonra kayboluyordu — merge logic ile düzeltildi (artık kalıcı)\n"
        "- 🐛 Duyuru gönderince 5 saniye sonra kayboluyordu — aynı fix uygulandı\n"
        "- 🐛 Yazı boyutu değişmiyordu — canlı güncelleme + önizleme eklendi\n\n"
        "**Yazı boyutu artık:**\n"
        "- 🔠 Ayarlarda seçince anında tüm açık sohbetlerde uygulanıyor\n"
        "- 👁️ Ayarlar ekranında \"ÖRNEK MESAJ\" önizleme kartı gösteriliyor\n\n"
        "**Dil desteği genişletildi:**\n"
        "- 🌐 Kişiler ve Ayarlar ekranında 45+ dil desteği eklendi (kısmi)"
    ),
}

HUAWEI_VERSIONS = {'v2.0.1', 'v2.0.2', 'v2.0.3', 'v2.0.4', 'v2.0.5', 'v3.0.0', 'v3.0.1', 'v3.0.2', 'v3.0.3', 'v3.0.4', 'v3.0.5', 'v4.0.0', 'v5.0.0', 'v6.0.0', 'v6.2.0', 'v6.3.0', 'v6.4.0', 'v6.5.0', 'v6.6.0', 'v7.0.0', 'v7.1.0', 'v7.2.0', 'v7.2.1', 'v8.0.0', 'v8.1.0', 'v8.2.0', 'v8.3.0', 'v9.0.0'}
INSTALLER_VERSIONS = {'v2.0.4', 'v2.0.5', 'v3.0.0', 'v3.0.1', 'v3.0.2', 'v3.0.3', 'v3.0.4', 'v3.0.5', 'v4.0.0', 'v5.0.0', 'v6.0.0', 'v6.2.0', 'v6.3.0', 'v6.4.0', 'v6.5.0', 'v6.6.0', 'v7.0.0', 'v7.1.0', 'v7.2.0', 'v7.2.1', 'v8.0.0', 'v8.1.0', 'v8.2.0', 'v8.3.0', 'v9.0.0'}


def make_body(tag):
    notes = CHANGELOGS.get(tag, f"### ✨ {tag} Yenilikleri\n- Genel iyileştirmeler ve hata düzeltmeleri")
    base = f"https://github.com/omer-faruk-g/photon-chat/releases/download/{tag}"
    huawei_row = f"| 📱 Huawei | [PhotonChat-Android.apk]({base}/PhotonChat-Android.apk) | ✅ İndir (GMS gerekmez) |\n" if tag in HUAWEI_VERSIONS else ""
    installer_row = f"| 🪟 Windows Kurulum | [PhotonChat-Windows-Setup.exe]({base}/PhotonChat-Windows-Setup.exe) | ✅ İndir |\n" if tag in INSTALLER_VERSIONS else ""
    return (
        "## 🔒 Photon Chat\n\n"
        "Güvenli, federe P2P mesajlaşma uygulaması. Telefon numarası gerekmez, hesap açılmaz.\n\n"
        + notes + "\n\n"
        "---\n\n"
        "### 📥 İndir\n\n"
        "| Platform | İndir | |\n"
        "|----------|-------|---|\n"
        f"| 🤖 Android | [PhotonChat-Android.apk]({base}/PhotonChat-Android.apk) | ✅ İndir |\n"
        + huawei_row +
        installer_row +
        f"| 🪟 Windows | [PhotonChat-Windows.zip]({base}/PhotonChat-Windows.zip) | ✅ İndir |\n"
        f"| 🐧 Linux | [PhotonChat-Linux.tar.gz]({base}/PhotonChat-Linux.tar.gz) | ✅ İndir |\n"
        "| 🍎 iOS | — | 🔜 Yakında |\n\n"
        "---\n\n"
        "### 🚀 Kurulum\n\n"
        "**Android / Huawei:** APK dosyasını indir → telefona yükle (Bilinmeyen kaynaklara izin ver)\n\n"
        "**Windows:** Kurulum için `PhotonChat-Windows-Setup.exe` çalıştır, ya da ZIP'i aç → `photon_chat.exe` çalıştır\n\n"
        "**Linux:** `tar -xzf PhotonChat-Linux.tar.gz` → `./photon_chat` çalıştır"
    )


def write_github_output(tag):
    body = make_body(tag)
    out = os.environ.get('GITHUB_OUTPUT', '')
    if out:
        with open(out, 'a') as f:
            f.write('body<<BODYEOF\n')
            f.write(body)
            f.write('\nBODYEOF\n')
    else:
        print(body)


def update_all(token, repo):
    req = urllib.request.Request(
        f'https://api.github.com/repos/{repo}/releases?per_page=100',
        headers={'Authorization': f'Bearer {token}', 'Accept': 'application/vnd.github+json'}
    )
    releases = json.loads(urllib.request.urlopen(req).read())
    for r in releases:
        tag = r['tag_name']
        if tag not in CHANGELOGS:
            print(f'Skipping {tag}')
            continue
        body = make_body(tag)
        payload = json.dumps({'body': body}).encode()
        patch = urllib.request.Request(
            f'https://api.github.com/repos/{repo}/releases/{r["id"]}',
            data=payload, method='PATCH',
            headers={
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.github+json',
                'Content-Type': 'application/json',
            }
        )
        urllib.request.urlopen(patch)
        print(f'Updated {tag}')


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'output'
    if mode == 'output':
        write_github_output(os.environ['TAG'])
    elif mode == 'update-all':
        update_all(os.environ['GH_TOKEN'], os.environ['REPO'])
