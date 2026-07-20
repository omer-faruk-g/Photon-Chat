import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translate_service.dart';

class AppLang extends ChangeNotifier {
  static final AppLang instance = AppLang._();
  AppLang._();

  String _lang = 'tr';
  String get lang => _lang;
  bool _translatingUi = false;
  bool get translatingUi => _translatingUi;

  static const _key = 'knk_lang_v1';
  static const _cachePrefix = 'knk_i18n_cache_';

  final Map<String, String> _translated = {};

  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'tr', 'name': 'Türkçe', 'flag': '🇹🇷'},
    {'code': 'en', 'name': 'English', 'flag': '🇬🇧'},
    {'code': 'ar', 'name': 'العربية', 'flag': '🇸🇦'},
    {'code': 'de', 'name': 'Deutsch', 'flag': '🇩🇪'},
    {'code': 'fr', 'name': 'Français', 'flag': '🇫🇷'},
    {'code': 'es', 'name': 'Español', 'flag': '🇪🇸'},
    {'code': 'pt', 'name': 'Português', 'flag': '🇧🇷'},
    {'code': 'it', 'name': 'Italiano', 'flag': '🇮🇹'},
    {'code': 'ru', 'name': 'Русский', 'flag': '🇷🇺'},
    {'code': 'zh', 'name': '中文', 'flag': '🇨🇳'},
    {'code': 'ja', 'name': '日本語', 'flag': '🇯🇵'},
    {'code': 'ko', 'name': '한국어', 'flag': '🇰🇷'},
    {'code': 'hi', 'name': 'हिन्दी', 'flag': '🇮🇳'},
    {'code': 'nl', 'name': 'Nederlands', 'flag': '🇳🇱'},
    {'code': 'pl', 'name': 'Polski', 'flag': '🇵🇱'},
    {'code': 'uk', 'name': 'Українська', 'flag': '🇺🇦'},
    {'code': 'sv', 'name': 'Svenska', 'flag': '🇸🇪'},
    {'code': 'da', 'name': 'Dansk', 'flag': '🇩🇰'},
    {'code': 'fi', 'name': 'Suomi', 'flag': '🇫🇮'},
    {'code': 'no', 'name': 'Norsk', 'flag': '🇳🇴'},
    {'code': 'el', 'name': 'Ελληνικά', 'flag': '🇬🇷'},
    {'code': 'cs', 'name': 'Čeština', 'flag': '🇨🇿'},
    {'code': 'ro', 'name': 'Română', 'flag': '🇷🇴'},
    {'code': 'hu', 'name': 'Magyar', 'flag': '🇭🇺'},
    {'code': 'th', 'name': 'ไทย', 'flag': '🇹🇭'},
    {'code': 'vi', 'name': 'Tiếng Việt', 'flag': '🇻🇳'},
    {'code': 'id', 'name': 'Bahasa Indonesia', 'flag': '🇮🇩'},
    {'code': 'ms', 'name': 'Bahasa Melayu', 'flag': '🇲🇾'},
    {'code': 'fa', 'name': 'فارسی', 'flag': '🇮🇷'},
    {'code': 'he', 'name': 'עברית', 'flag': '🇮🇱'},
    {'code': 'bg', 'name': 'Български', 'flag': '🇧🇬'},
    {'code': 'hr', 'name': 'Hrvatski', 'flag': '🇭🇷'},
    {'code': 'sr', 'name': 'Српски', 'flag': '🇷🇸'},
    {'code': 'sk', 'name': 'Slovenčina', 'flag': '🇸🇰'},
    {'code': 'az', 'name': 'Azərbaycan', 'flag': '🇦🇿'},
    {'code': 'ka', 'name': 'ქართული', 'flag': '🇬🇪'},
    {'code': 'sq', 'name': 'Shqip', 'flag': '🇦🇱'},
    {'code': 'mk', 'name': 'Македонски', 'flag': '🇲🇰'},
    {'code': 'bs', 'name': 'Bosanski', 'flag': '🇧🇦'},
    {'code': 'ku', 'name': 'Kurdî', 'flag': '🏳️'},
    {'code': 'af', 'name': 'Afrikaans', 'flag': '🇿🇦'},
    {'code': 'sw', 'name': 'Kiswahili', 'flag': '🇰🇪'},
    {'code': 'bn', 'name': 'বাংলা', 'flag': '🇧🇩'},
    {'code': 'ur', 'name': 'اردو', 'flag': '🇵🇰'},
    {'code': 'fil', 'name': 'Filipino', 'flag': '🇵🇭'},
  ];

  Future<void> setLang(String lang) async {
    _lang = lang;
    _translated.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);

    if (lang == 'tr') {
      notifyListeners();
      return;
    }

    final cached = prefs.getString('$_cachePrefix$lang');
    if (cached != null) {
      try {
        final map = (jsonDecode(cached) as Map).cast<String, String>();
        _translated.addAll(map);
        notifyListeners();
        return;
      } catch (_) {}
    }

    _translatingUi = true;
    notifyListeners();

    await _translateAllKeys(lang, prefs);

    _translatingUi = false;
    notifyListeners();
  }

  Future<void> _translateAllKeys(String lang, SharedPreferences prefs) async {
    final allValues = _baseTr.values.toList();
    final allKeys = _baseTr.keys.toList();

    final batch = allValues.join('\n||||\n');
    try {
      final result = await TranslateService.translate(batch, targetLang: lang);
      final parts = result.split('\n||||\n');
      if (parts.length == allKeys.length) {
        for (var i = 0; i < allKeys.length; i++) {
          _translated[allKeys[i]] = parts[i].trim();
        }
      } else {
        for (var i = 0; i < allKeys.length; i++) {
          final tr = await TranslateService.translate(allValues[i], targetLang: lang);
          _translated[allKeys[i]] = tr;
        }
      }
      await prefs.setString('$_cachePrefix$lang', jsonEncode(_translated));
    } catch (_) {}
  }

  static Future<void> loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      instance._lang = saved;
      if (saved != 'tr') {
        final cached = prefs.getString('$_cachePrefix$saved');
        if (cached != null) {
          try {
            final map = (jsonDecode(cached) as Map).cast<String, String>();
            instance._translated.addAll(map);
          } catch (_) {}
        }
      }
    }
  }

  String t(String key) {
    if (_lang == 'tr') return _baseTr[key] ?? key;
    return _translated[key] ?? _baseTr[key] ?? key;
  }

  static const Map<String, String> _baseTr = {
    'contacts': 'Kişiler',
    'addContact': 'Kişi Ekle',
    'settings': 'Ayarlar',
    'send': 'Gönder',
    'writeMessage': 'Mesaj yaz…',
    'darkMode': 'Karanlık mod',
    'lightMode': 'Aydınlık mod',
    'language': 'Dil',
    'profile': 'Profil',
    'statusMessage': 'DURUM MESAJI',
    'deactivateAccount': 'Hesabı bu cihazdan kaldır',
    'copy': 'Kodunu Kopyala',
    'copyMessage': 'Kopyala',
    'codeLabel': 'Kod',
    'cancel': 'Vazgeç',
    'confirm': 'Onayla',
    'serverSetup': 'Sunucu Ayarı',
    'serverUrl': 'Sunucu URL',
    'connectAndContinue': 'Bağlan ve Devam Et',
    'urlEmpty': 'URL boş olamaz',
    'serverNotResponding': 'Sunucu yanıt vermiyor',
    'connectionError': 'Bağlantı hatası',
    'onboarding': 'Başlangıç',
    'createIdentity': 'Kimlik Oluştur',
    'displayName': 'Görünen Ad',
    'regenerate': 'Yenile',
    'matchCode': 'Eşleşme Kodu',
    'yourAddress': 'SENİN ADRESİN',
    'copyAddress': 'Adresi Kopyala',
    'guide': 'Rehber',
    'groups': 'Gruplar',
    'createGroup': 'Grup Oluştur',
    'joinGroup': 'Gruba Katıl',
    'block': 'Engelle',
    'unblock': 'Engeli Kaldır',
    'mute': 'Sustur',
    'unmute': 'Susturmayı Kaldır',
    'kick': 'At',
    'newMessage': 'Yeni Mesaj',
    'kickedFromGroup': 'Gruptan atıldınız',
    'mutedInGroup': 'Grupta susturuldunuz',
    'notification': 'Bildirim',
    'poll': 'Anket',
    'announcement': 'Duyuru',
    'vote': 'Oy Ver',
    'results': 'Sonuçlar',
    'createPoll': 'Anket Oluştur',
    'createAnnouncement': 'Duyuru Oluştur',
    'deleteMessage': 'Mesajı Sil',
    'editMessage': 'Mesajı Düzenle',
    'reply': 'Yanıtla',
    'reactions': 'Tepkiler',
    'search': 'Ara',
    'wallpaper': 'Duvar Kağıdı',
    'offlineQueue': 'Çevrimdışı Kuyruk',
    'translate': 'Çevir',
    'translating': 'Çevriliyor…',
    'selectLanguage': 'Dil Seçin',
    'chatWallpaper': 'Sohbet Duvar Kağıdı',
    'chooseWallpaper': 'Duvar Kağıdı Seç',
    'defaultWallpaper': 'Varsayılan',
    'solidColor': 'Düz Renk',
    'gallery': 'Galeri',
    'offlineMessageWillSend': 'Çevrimiçi olunca gönderilecek',
    'pendingMessages': 'Bekleyen Mesajlar',
    'messageTranslation': 'Mesaj Çevirisi',
    'typeMessage': 'Mesaj yazın…',
    'editingMessage': 'Mesaj düzenleniyor…',
    'contactInactive': 'Kişi aktif değil',
    'blockedContact': 'Engellenen kişi',
    'save': 'Kaydet',
    'done': 'Tamam',
    'error': 'Hata',
    'loading': 'Yükleniyor…',
    'retry': 'Tekrar Dene',
    'yes': 'Evet',
    'no': 'Hayır',
    'ok': 'Tamam',
    'deactivateConfirm': 'FIP bloğun, kişi listen ve aktif sohbetlerin kalıcı olarak silinir.',
    'logoutConfirm': 'Çıkış yapmak istediğinize emin misiniz?',
    'deleteConfirm': 'Evet, sil',
    // AppBar titles
    'chat': 'Sohbet',
    'groupChat': 'Grup Sohbeti',
    'devices': 'Cihazlar',
    'stories': 'Hikayeler',
    'starredMessages': 'Yıldızlı Mesajlar',
    'setLock': 'Kilit Ayarla',
    // Buttons
    'add': 'Ekle',
    'delete': 'Sil',
    'remove': 'Kaldır',
    'close': 'Kapat',
    'continueLabel': 'Devam',
    'reject': 'Reddet',
    'accept': 'Kabul Et',
    'leave': 'Ayrıl',
    'join': 'Katıl',
    'share': 'Paylaş',
    'copyLabel': 'Kopyala',
    // Section headers
    'bioSection': 'BIO',
    'fontSizeSection': 'YAZI BOYUTU',
    'languageSection': 'DIL',
    'themeSection': 'TEMA',
    'notificationSoundSection': 'BİLDİRİM SESİ',
    'quickRepliesSection': 'HIZLI YANITLAR',
    'appLockSection': 'UYGULAMA KİLİDİ',
    // Common
    'joinGroupShort': 'Gruba Katıl',
    'addStory': 'Hikaye Ekle',
    'addYourStory': 'Hikayeni Ekle',
    'small': 'Küçük',
    'medium': 'Orta',
    'large': 'Büyük',
    'online': 'Çevrimiçi',
    'offline': 'Çevrimdışı',
    'today': 'Bugün',
    'yesterday': 'Dün',
    'typing': 'yazıyor…',
    // Menu verbs
    'star': 'Yıldızla',
    'unstar': 'Yıldızı Kaldır',
    'edit': 'Düzenle',
    'replyVerb': 'Cevapla',
    'translateVerb': 'Çevir',
    'deleteVerb': 'Sil',
    'pin': 'Sabitle',
    'unpin': 'Sabitlemeyi kaldır',
    'disappearingDuration': 'Kaybolan mesaj süresi',
    'removeAccountFromDevice': 'Hesabı bu cihazdan kaldır',
    // Snackbars/toasts
    'inviteSent': 'kullanıcısına davet gönderildi',
    'blocked': 'engellendi',
    'addedToFriends': 'arkadaş listene eklendi',
    'groupJoinRequestSent': 'grubuna katılma isteği gönderildi',
    'muted': 'susturuldu',
    'kickedFromGroupToast': 'gruptan atıldı',
    'demoted': 'moderatörlükten alındı',
    'promoted': 'moderatör yapıldı',
    'pollSent': 'Anket gönderildi',
    'announcementSent': 'Duyuru gönderildi',
    'copied': 'kopyalandı',
    // Errors
    'invalidServerAddress': 'Sunucu adresi geçersiz',
    'genericError': 'Bir hata oluştu',
    // Chat
    'writeMessagePlaceholder': 'Mesaj yaz...',
    'sendAnnouncement': 'Duyuru Gönder',
    'inviteLink': 'Davet Linki',
    'announcementTitle': 'Duyuru',
    'pollTitle': 'Anket',
    'question': 'Soru',
    'option': 'Seçenek',
    'addOption': 'Seçenek Ekle',
    // Contacts screen
    'noContacts': 'Henüz kişi yok',
    // Add contact
    'contactAddress': 'Kişi Adresi',
    'contactName': 'Kişi Adı',
    // Create group
    'groupName': 'Grup Adı',
    // Lock
    'enterPin': 'PIN Girin',
    'drawPattern': 'Deseni Çizin',
    'wrongPin': 'Yanlış PIN',
    'wrongPattern': 'Yanlış desen',
    // Starred
    'noStarredMessages': 'Yıldızlı mesaj yok',
    'noStarredMessagesYet': 'Yıldızlı mesajın yok.',
    // Add contact
    'myQrCode': 'BENİM QR KODUM',
    'qrHint': 'Arkadaşın bu kodu veya QR\'ı tarayarak seni ekleyebilir.',
    'sendInvite': 'Davet gönder',
    // Create group
    'createGroupHint': 'Grup adı gir. Oluşturulduktan sonra paylaşabilecegin 7 haneli bir kod alacaksın.',
    'groupDescriptionOptional': 'Grup Açıklaması (isteğe bağlı)',
    'groupDescriptionHint': 'Kısa bir tanım yazabilirsin…',
    'create': 'Oluştur',
    'groupCreatedShareBelow': 'Grup oluşturuldu! Aşağıdaki adresi arkadaşlarınla paylaş.',
    'groupAddress': 'GRUP ADRESİ',
    // Join group
    'inviteLinkOrCode': 'DAVET LİNKİ VEYA GRUP KODU',
    'inviteLinkHint': 'photon://1234567@https://… veya sadece 1234567',
    'groupOwnerServer': 'GRUP SAHİBİNİN SUNUCU ADRESİ',
    'ownerServerHint': 'https://sunucu.onrender.com',
    'sendJoinRequest': 'Katılma İsteği Gönder',
    // Onboarding
    'identityCreateFailed': 'Kimlik oluşturulamadı',
    'fipPreview': 'FIP — ÖNİZLEME',
    'displayNameFriendsOnly': 'Görünen ad (sadece arkadaşların görür)',
    'createIdentityOnDevice': 'Kimliği bu cihazda oluştur',
    'yourCode': 'SENİN KODUN',
    'copyCode': 'Kodu Kopyala',
    'continueArrow': 'Devam →',
    'regenerateShort': 'yeniden üret',
    // Guide
    'guideSetupServer': 'Kendi Sunucunu Kur (Bir Kez)',
    'guideYourCode': 'Senin Kodun',
    'guideAddFriend': 'Arkadaş Ekle',
    'guideGroupChats': 'Grup Sohbetleri',
    'guidePrivacy': 'Gizlilik',
    'skip': 'Atla',
    // Server setup
    'serverSetupTitle': 'Sunucu Kurulumu',
    'renderUrl': 'Render URL',
    'renderUrlHint': 'https://photon-chat-xxxx.onrender.com',
    // Lock
    'confirmPin': 'PIN\'i Onaylayın',
    'newPinEnter': 'Yeni PIN Girin (4-6 hane)',
    'confirmPattern': 'Deseni Onaylayın',
    'newPatternDraw': 'Yeni Desen Çizin (en az 3 nokta)',
    // Wallpaper
    'photoTooLarge': 'Fotoğraf çok büyük (max 300KB)',
    'defaultLabel': 'Varsayılan',
    'colors': 'Renkler',
    'pickFromGallery': 'Galeriden Seç',
    // Chat generic
    'locationServiceOff': 'Konum servisi kapalı.',
    'locationPermissionDenied': 'Konum izni reddedildi.',
    'locationPermissionPermanent': 'Konum izni kalıcı olarak reddedildi.',
    'locationFailed': 'Konum alınamadı',
    'voiceRecordStartFailed': 'Ses kaydı başlatılamadı',
    'sendImage': 'Görsel Gönder',
    'markSensitive': 'Hassas / +18 içerik olarak işaretle',
    'cancelShort': 'İptal',
    'sendShort': 'Gönder',
    'imageTooLarge': 'Görsel çok büyük (maks 3 MB)',
    'fileTooLarge': 'Dosya çok büyük (maks 50 MB)',
    'encryptionError': 'Şifreleme hatası, mesaj gönderilemedi.',
    'editFailed': 'Düzenleme başarısız',
    'reactionFailed': 'Reaksiyon gönderilemedi',
    'translation': 'çeviri',
    'edited': 'düzenlendi · ',
    'forward': 'İlet',
    'unstarShort': 'Yıldızı Kaldır',
    'starShort': 'Yıldızla',
    'deleteFailed': 'Silme başarısız',
    'forwardTo': 'Kime ilet?',
    'noActiveContacts': 'Aktif kişin yok.',
    'code': 'Kod',
    'disappearingMessages': 'Kaybolan Mesajlar',
    'off': 'Kapalı',
    'lastSeenUnknown': 'Son görülme bilinmiyor',
    'justNow': 'az önce',
    'contactInactiveTitle': 'Kişi artık aktif değil',
    'contactRemovedDevice': 'Bu kişi hesabını bu cihazdan kaldırdı.',
    'sensitiveContentTap': 'Hassas içerik\nGörmek için dokun',
    'tapToView': 'Görmek için dokun',
    'sharedLocation': 'Konumunu Paylaştı',
    'openInMap': 'Haritada Aç',
    'voiceMessage': 'Sesli Mesaj',
    'fileOpenFailed': 'Dosya açılamadı',
    'exportChat': 'Sohbeti Dışa Aktar',
    'blockedByYou': 'Bu kişiyi engellediniz.',
    'editMode': 'Düzenleme modu',
    'unblockToSee': 'Bu kişiyi engellediniz.\nMesajlarını görmek için engeli kaldırın.',
    'chatCleanStart': 'Bu sohbet temiz. İlk mesajı sen gönder.',
    'you': 'Sen',
    'sendPhoto': 'Fotoğraf Gönder',
    'sendFile': 'Dosya Gönder',
    'createGif': 'GIF Oluştur',
    'shareLocation': 'Konum Paylaş',
    'quickReplies': 'Hızlı Yanıtlar',
    'blockedHint': 'Bu kişiyi engellediniz.',
    'editingMessageHint': 'Mesajı düzenle…',
    'listening': '🎙 Dinliyor…',
    'contactInactiveHint': 'Kişi artık aktif değil…',
    // Group
    'joinRequests': 'Katılma İstekleri',
    'noPendingRequests': 'Bekleyen istek yok.',
    'unknown': 'Bilinmeyen',
    'modRemove': 'MOD Kaldır',
    'modMake': 'MOD Yap',
    'members': 'ÜYELER',
    'modBadge': 'MOD',
    'sendAnnouncementTitle': 'Duyuru Gönder',
    'announcementTextHint': 'Duyuru metni…',
    'createPollTitle': 'Anket Oluştur',
    'questionHint': 'Soru…',
    'optionN': 'Seçenek',
    'optionOptional': '(opsiyonel)',
    'pollLabel': 'ANKET',
    'inviteLinkTitle': 'Davet Linki',
    // Stories
    'textStory': 'Metin Hikaye',
    'imageStory': 'Görsel Hikaye',
    'writeStoryHint': 'Hikayeni yaz...',
    'shareStory': 'Paylaş',
    'nsfwDetected': 'Uygunsuz içerik tespit edildi — paylaşılmadı.',
    'noStories': 'Hikaye bulunamadı',
    'imageLoadFailed': 'Görsel yüklenemedi',
    // Devices
    'verificationCodeAttempt': 'Doğrulama Kodu',
    'attempt': 'Deneme',
    'enterCodeOnOtherDevice': 'Bu kodu diğer cihaza gir',
    'kickDevice': 'Cihazı At',
    'kickShort': 'At',
    'deviceManagement': 'Cihaz Yönetimi',
    'noLinkedDevices': 'Bağlı yan cihaz yok',
    'linkedDevicesHint': 'Başka bir cihaz aynı server URL\'sine bağlanmaya çalıştığında burada görünecek.',
    'noFakeAccounts': 'Fake hesap yok',
    'fakeAccountsHint': 'Yanlış kod giren veya reddedilen cihazlar burada FAKE olarak görünür.',
    'noPendingRequestsShort': 'Bekleyen istek yok',
    'deviceWantsToConnect': 'Bu cihaz senin serverına bağlanmak istiyor.',
    'approveSendCode': 'Onayla (Kod Gönder)',
    'rejectFake': 'Reddet (FAKE)',
    'fakeBadge': 'FAKE',
    'connectedAt': 'Bağlandı',
    'activity': 'Aktivite',
    'records': 'kayıt',
    'noActivity': 'Henüz aktivite yok',
    // Device link
    'devicePairedSuccess': 'Cihaz başarıyla eşleştirildi!',
    'deviceLinking': 'Cihaz Bağlama',
    'serverAlreadyRegistered': 'Bu Server Zaten Kayıtlı',
    'howItWorks': 'NASIL ÇALIŞIR?',
    'sending': 'Gönderiliyor…',
    'sendConnectionRequest': 'Bağlantı İsteği Gönder',
    'enterCodeFromMain': 'Ana cihazdan aldığın kodu gir',
    'verifyCode': 'Kodu Doğrula',
    'permanentFake': 'Kalıcı FAKE',
    'codeMustBe5': 'Kod tam olarak 5 rakamdan oluşmalıdır',
    'thatIsYourCode': 'Bu senin kendi kodun.',
    'noActiveUserWithCode': 'Bu koda sahip aktif bir kullanıcı bulunamadı.',
    'inviteFailed': 'Davet gönderilemedi',
    'friendCode5Digit': 'ARKADAŞININ 5 HANELİ KODU',
    'friendCodeHint': 'Arkadaşının profilindeki 5 haneli kodu gir. Davet isteği otomatik olarak onun sunucusuna gönderilir.',
    'myQrTooltip': 'Benim QR Kodum',
    'scanFriendQr': 'Arkadaşının QR\'ını Tara',
    'groupNameEmpty': 'Grup adı boş olamaz',
    'groupCreateFailed': 'Grup oluşturulamadı',
    'groupCode7Required': 'Grup kodu 7 haneli olmalıdır',
    'ownerServerMissing': 'Grup sahibinin sunucu adresi eksik',
    'groupNotFound': 'Grup bulunamadı. Davet linkini kontrol et.',
    'joinGroupIntro': 'Grup sahibinin paylaştığı davet linkini yapıştır — otomatik tanınır.\n\nDavet linki yoksa 7 haneli grup kodunu yaz.',
    'group': 'Grup',
    'urlMustStartHttps': "URL 'https://' ile başlamalı",
    'invalidUrlFormat': 'Geçersiz URL biçimi',
    'serverBanned': 'Bu sunucuya erişiminiz kalıcı olarak yasaklanmış.',
    'serverNoResponse': 'Sunucu yanıt vermedi',
    'photonChatOwnServer': 'Photon Chat kendi sunucunu kullanır.\n\nrender.com üzerinde ücretsiz bir Node.js servisi aç ve adresini buraya gir.',
    'renderSteps': '1. render.com → New → Web Service\n2. GitHub reposunu seç (server/ klasörü)\n3. Free plan → Deploy\n4. Verilen URL\'yi buraya yapıştır',
    // Onboarding extras
    'photonChatTagline': 'FIP tabanlı kimlik · sunucusuz rehber · numarasız',
    'displayNameExample': 'örn. Photon',
    'onboardingPrivacyNote': 'Bu işlem internet hesabı, telefon numarası ya da e-posta gerektirmez. FIP bloğun ve eşleşme kodun bu cihazda saklanır.',
    'shareCodeWithFriends': 'Bu kodu arkadaşlarınla paylaş',
    'matchCodeUpper': 'EŞLEŞME KODU',
    // Guide
    'guideWelcomeTitle': "Photon Chat'e Hoş Geldin",
    'guideWelcomeBody': 'Telefon numarası yok. E-posta yok. Hesap yok.\n\nSadece bir kriptografik kimlik — cihazında oluşturulur, kimseyle paylaşılmaz.',
    'guideServerBody': 'Photon Chat merkezi bir sunucu kullanmaz.\n\nrender.com üzerinde ücretsiz kendi sunucunu çalıştır. Bu kurulumu yalnızca bir kez yapman yeterli — sonraki açılışlarda tekrar sorulmaz.\n\nAdımlar:\n1. render.com → New → Web Service\n2. GitHub reposunu bağla\n3. Root Directory: server\n4. Build Command: npm install\n5. Start Command: node index.js\n6. Plan: Free → Deploy',
    'guideServerTip': 'Root Directory mutlaka "server" olmalı!',
    'guideCodeBody': 'Kimliğin oluşturulunca sana 5 haneli bir eşleşme kodu verilir.\n\nBu kod senin tek adresindir. Arkadaşlarına sadece bu kodu ver — başka bir şey gerekmez.',
    'guideAddFriendBody': 'Arkadaşının 5 haneli kodunu gir — ya da QR kodunu tara.\n\nİstek bridge üzerinden iletilir. Kabul ederse ikiniz bağlanırsınız.\n\nSunucu URL\'si paylaşmanıza gerek yok.',
    'guideGroupBody': 'Gruplar merkeziyetsizdir — her üyenin sunucusu grubun bir parçasını taşır.\n\n• Grup oluştur → sana 7 haneli bir kod verilir\n• Bu kodu paylaş → üyeler katılmak için gönderir\n• Sen kabul et → mesajlaşma başlar',
    'guidePrivacyBody': "Sunucu hiçbir veriyi kalıcı olarak saklamaz — her şey RAM'dedir.\n\n• Uygulama kapatılırken sohbetleri imha edebilirsin\n• Hesabı sil → tüm veriler anında yok edilir\n• Kişi listesi yalnızca cihazında tutulur\n• Sunucu sadece şifreli blob'ları iletir",
    'letsStart': 'Hadi Başlayalım →',
    // Chat extras
    'sensitiveImageTag': '[Hassas Görsel]',
    'photoTag': '[Fotoğraf]',
    'nsfwSystemWarning': '⚠️ Sistem uyarısı: Önceki mesajda hassas/+18 içerik tespit edildi.',
    'sensitiveWarning': '⚠️ Karşı tarafa siyah blok olarak gönderilir ve uyarı mesajı iletilir.',
    'forwardedPrefix': '↗️ İletildi:',
    'forwardedToPerson': 'kişisine iletildi',
    'imageLoadFailedInline': '[Görsel yüklenemedi]',
    'lastSeenPrefix': 'Son görülme:',
    'minutesAgo': 'dk önce',
    'hoursAgo': 'saat önce',
    'daysAgo': 'gün önce',
    'removedAccountSuffix': 'hesabını kaldırdı.',
    'typingSuffix': 'yazıyor…',
    'disappear10s': '10 saniye',
    'disappear30s': '30 saniye',
    'disappear1m': '1 dakika',
    'disappear5m': '5 dakika',
    'disappear1h': '1 saat',
    // Group extras
    'voteSending': 'Oy gönderiliyor…',
    'voteFailed': 'Oy gönderilemedi.',
    'muteFailed': 'Susturulamadı.',
    'unmutedUserSuffix': 'susturma kaldırıldı.',
    'actionFailed': 'İşlem başarısız.',
    'removedFromGroupTitle': 'Gruptan çıkarıldınız',
    'removedFromGroupBodySuffix': 'grubundan çıkarıldınız',
    'kickedFromGroupUserSuffix': 'gruptan atıldı.',
    'kickFailed': 'Çıkarma başarısız.',
    'unmuteUserSuffix': 'susturmayı kaldır',
    'muteUserSuffix': 'kullanıcısını sustur',
    'kickUserSuffix': 'kullanıcısını gruptan at',
    'linkCopied': 'Link kopyalandı!',
    'announcementSentDot': 'Duyuru gönderildi.',
    'pollSentDot': 'Anket gönderildi.',
    'votesCastSuffix': 'oy kullandı',
    // Devices
    'attemptOfThree': 'Deneme',
    'enterCodeDigitsPrefix': 'Bu',
    'enterCodeDigitsSuffix': 'haneli kodu diğer cihaza gir:',
    'tryingToConnectSuffix': 'bağlanmaya çalışıyor',
    'lastChance': 'Son şans!',
    'nextWillBe15': 'Bir sonraki 15 haneli olacak',
    'kickDeviceConfirmSuffix': 'cihazını atmak istediğine emin misin?\n\nAtılan cihaz bir daha bu servera bağlanamaz.',
    'bannedSuffix': 'banlandı',
    'requestsTab': 'İstekler',
    'watch': 'İzle',
    'giveMod': 'MOD Ver',
    'connectedAtLabel': 'Bağlandı:',
    'activityLabel': 'Aktivite:',
    'recordsSuffix': 'kayıt',
    // Device link
    'codeMustBeDigitsPrefix': 'Kod',
    'codeMustBeDigitsSuffix': 'haneli olmalı',
    'threeWrongTriesFake': '3 yanlış deneme — kalıcı FAKE olarak işaretlendiniz',
    'codeWrongTryAgainPrefix': 'Kod yanlış! Ana cihazdan',
    'codeWrongTryAgainSuffix': 'haneli yeni kod al.',
    'serverAlreadyHasAccount': 'Bu sunucuda zaten bir hesap mevcut. Yan cihaz olarak bağlanmak için ana cihazdan onay gerekiyor.',
    'linkStep1': 'Bağlantı isteği gönder',
    'linkStep2': 'Ana cihaz sana doğrulama kodu verecek',
    'linkStep3': 'Kodu bu ekrana gir',
    'linkStep4': 'Kod doğruysa yan cihaz olarak bağlan',
    'threeWrongWarn': '3 yanlış denemede kalıcı FAKE olarak işaretlenirsin!',
    'enterCodeFromMainPrefix': 'Ana cihazdan aldığın',
    'enterCodeFromMainSuffix': 'haneli kodu gir:',
    'permanentFakeBody': '3 yanlış deneme yaptınız.\nBu cihaz kalıcı olarak FAKE olarak işaretlendi.\nAna hesabın hiçbir yetkisini göremezsiniz.',
    // Lock
    'wrongTriesPrefix': 'yanlış deneme —',
    'waitSecondsSuffix': 's bekleyin.',
    'wrongRetry': 'Tekrar deneyin.',
    'pinLabel': 'PIN',
    'patternLabel': 'desen',
    'pinsDontMatch': 'PIN\'ler eşleşmiyor. Tekrar deneyin.',
    'patternsDontMatch': 'Desenler eşleşmiyor. Tekrar deneyin.',
    // Wallpaper
    'wallpaperPreview': 'Duvar Kağıdı Önizleme',
    // Chat menu
    'chatContactRemovedNamed': 'hesabını kaldırdı.',
    'forwardedToPersonComposed': 'kişisine iletildi',
  };
}
