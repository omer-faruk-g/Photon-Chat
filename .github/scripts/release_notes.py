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
}

HUAWEI_VERSIONS = {'v2.0.1', 'v2.0.2', 'v2.0.3', 'v2.0.4', 'v2.0.5', 'v3.0.0'}
INSTALLER_VERSIONS = {'v2.0.4', 'v2.0.5', 'v3.0.0'}


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
