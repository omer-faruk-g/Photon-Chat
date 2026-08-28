import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translate_service.dart';
import 'profanity_filter.dart';

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

  double _translateProgress = 0.0;
  double get translateProgress => _translateProgress;
  String _translateStatus = '';
  String get translateStatus => _translateStatus;

  /// Returns true on success, false on failure (in which case the previous
  /// language is preserved so the UI is never stuck on Turkish "translated" text).
  Future<bool> setLang(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    // Fast path: Turkish base — no network needed.
    if (lang == 'tr') {
      _lang = lang;
      _translated.clear();
      await prefs.setString(_key, lang);
      await reloadProfanityForCurrentLang();
      notifyListeners();
      return true;
    }
    // Cached translation exists — instant switch.
    final cached = prefs.getString('$_cachePrefix$lang');
    if (cached != null) {
      try {
        final map = (jsonDecode(cached) as Map).cast<String, String>();
        _lang = lang;
        _translated
          ..clear()
          ..addAll(map);
        await prefs.setString(_key, lang);
        await reloadProfanityForCurrentLang();
        notifyListeners();
        return true;
      } catch (_) {}
    }

    // No cache — must translate all keys. Show progress screen.
    final previousLang = _lang;
    final previousMap = Map<String, String>.from(_translated);
    _translatingUi = true;
    _translateProgress = 0.0;
    _translateStatus = _baseTr['translateStarting'] ?? 'Çeviri başlıyor…';
    notifyListeners();

    final ok = await _translateAllKeysStrict(lang, prefs);
    if (ok) {
      _lang = lang;
      await prefs.setString(_key, lang);
      await reloadProfanityForCurrentLang();
    } else {
      // Rollback — never leave the app on an untranslated fake language.
      _translated
        ..clear()
        ..addAll(previousMap);
      _lang = previousLang;
    }
    _translatingUi = false;
    _translateProgress = 0.0;
    notifyListeners();
    return ok;
  }

  static const _batchSeparator = '\n||||\n';

  /// Strings per batched request. The previous code put *every* value in one
  /// request, which blew past the endpoint's URL limit — so the batch always
  /// failed and every switch fell back to one request per string. With 417 keys
  /// that was 417 round-trips: slow enough to take over a minute, and enough
  /// volume to get rate-limited mid-switch. Chunking keeps each URL small while
  /// cutting the request count by ~20x.
  static const _batchSize = 20;

  Future<bool> _translateAllKeysStrict(String lang, SharedPreferences prefs) async {
    final allValues = _baseTr.values.toList();
    final allKeys = _baseTr.keys.toList();
    final newMap = <String, String>{};
    final total = allKeys.length;
    var done = 0;

    void reportProgress() {
      _translateProgress = total == 0 ? 1.0 : done / total;
      // Deliberately reads the base map rather than t(): during a switch the
      // target language is not active yet, so this stays in the language the
      // user is still looking at.
      _translateStatus = '${_baseTr['translating'] ?? 'Çeviriliyor'} $done / $total';
    }

    // Per-string fallback for a chunk the batched request could not round-trip.
    Future<void> translateIndividually(Iterable<int> indexes) async {
      const concurrency = 8;
      final list = indexes.toList();
      for (var i = 0; i < list.length; i += concurrency) {
        final inFlight = <Future<void>>[];
        for (var j = i; j < i + concurrency && j < list.length; j++) {
          final k = list[j];
          inFlight.add(TranslateService.translateStrict(allValues[k], targetLang: lang).then((tr) {
            newMap[allKeys[k]] = tr;
            done++;
            reportProgress();
          }));
        }
        await Future.wait(inFlight);
        notifyListeners();
      }
    }

    try {
      for (var start = 0; start < total; start += _batchSize) {
        final end = start + _batchSize < total ? start + _batchSize : total;
        final indexes = [for (var i = start; i < end; i++) i];
        var batched = false;
        try {
          final joined = [for (final i in indexes) allValues[i]].join(_batchSeparator);
          final result = await TranslateService.translateStrict(joined, targetLang: lang);
          final parts = result.split(_batchSeparator);
          // Only trust the batch when the separator survived intact; otherwise
          // the pieces would be misaligned and every label would be wrong.
          if (parts.length == indexes.length) {
            for (var n = 0; n < indexes.length; n++) {
              newMap[allKeys[indexes[n]]] = parts[n].trim();
            }
            done += indexes.length;
            batched = true;
          }
        } catch (_) {
          // fall through to the per-string path for this chunk only
        }
        if (batched) {
          reportProgress();
          notifyListeners();
        } else {
          await translateIndividually(indexes);
        }
      }
      _translated
        ..clear()
        ..addAll(newMap);
      await prefs.setString('$_cachePrefix$lang', jsonEncode(_translated));
      return true;
    } catch (_) {
      return false;
    }
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

  /// Display name for a language in the picker. Falls back to the endonym
  /// ([nativeName]) for languages that have no `language_<code>` entry, so the
  /// list stays readable instead of showing a raw key.
  String languageLabel(String code, String nativeName) {
    final key = 'language_$code';
    if (!_baseTr.containsKey(key)) return nativeName;
    return t(key);
  }

  static const Map<String, String> _baseTr = {
    'addContact': 'Kişi Ekle',
    'settings': 'Ayarlar',
    'writeMessage': 'Mesaj yaz…',
    'darkMode': 'Karanlık mod',
    'lightMode': 'Aydınlık mod',
    'language': 'Dil',
    'statusMessage': 'DURUM MESAJI',
    'copyMessage': 'Kopyala',
    'codeLabel': 'Kod',
    'cancel': 'Vazgeç',
    'confirm': 'Onayla',
    'connectAndContinue': 'Bağlan ve Devam Et',
    'urlEmpty': 'URL boş olamaz',
    'connectionError': 'Bağlantı hatası',
    'copyAddress': 'Adresi Kopyala',
    'groups': 'Gruplar',
    'createGroup': 'Grup Oluştur',
    'joinGroup': 'Gruba Katıl',
    'block': 'Engelle',
    'reply': 'Yanıtla',
    'translating': 'Çevriliyor…',
    'selectLanguage': 'Dil Seçin',
    'chatWallpaper': 'Sohbet Duvar Kağıdı',
    'save': 'Kaydet',
    'error': 'Hata',
    'no': 'Hayır',
    'yes': 'Evet',
    'pollBadge': 'ANKET',
    'ok': 'Tamam',
    // AppBar titles
    'devices': 'Cihazlar',
    'starredMessages': 'Yıldızlı Mesajlar',
    'setLock': 'Kilit Ayarla',
    // Buttons
    'add': 'Ekle',
    'delete': 'Sil',
    'remove': 'Kaldır',
    'close': 'Kapat',
    'accept': 'Kabul Et',
    'share': 'Paylaş',
    // Section headers
    'bioSection': 'BIO',
    'fontSizeSection': 'YAZI BOYUTU',
    'themeSection': 'TEMA',
    'appLockSection': 'UYGULAMA KİLİDİ',
    // Common
    'addYourStory': 'Hikayeni Ekle',
    'online': 'Çevrimiçi',
    'offline': 'Çevrimdışı',
    'typing': 'yazıyor…',
    // Menu verbs
    'star': 'Yıldızla',
    'unstar': 'Yıldızı Kaldır',
    'edit': 'Düzenle',
    'translateVerb': 'Çevir',
    'pin': 'Sabitle',
    'unpin': 'Sabitlemeyi kaldır',
    // Snackbars/toasts
    // Errors
    // Chat
    'writeMessagePlaceholder': 'Mesaj yaz...',
    'sendAnnouncement': 'Duyuru Gönder',
    'inviteLink': 'Davet Linki',
    'addOption': 'Seçenek Ekle',
    // Contacts screen
    // Add contact
    // Create group
    'groupName': 'Grup Adı',
    // Lock
    'enterPin': 'PIN Girin',
    'drawPattern': 'Deseni Çizin',
    'wrongPin': 'Yanlış PIN',
    'wrongPattern': 'Yanlış desen',
    // Starred
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
    'forward': 'İlet',
    'deleteFailed': 'Silme başarısız',
    'noActiveContacts': 'Aktif kişin yok.',
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
    'createPollTitle': 'Anket Oluştur',
    'questionHint': 'Soru…',
    'optionN': 'Seçenek',
    'optionOptional': '(opsiyonel)',
    // Stories
    'textStory': 'Metin Hikaye',
    'imageStory': 'Görsel Hikaye',
    'writeStoryHint': 'Hikayeni yaz...',
    // Devices
    'verificationCodeAttempt': 'Doğrulama Kodu',
    'attempt': 'Deneme',
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
    'noActivity': 'Henüz aktivite yok',
    // Device link
    'devicePairedSuccess': 'Cihaz başarıyla eşleştirildi!',
    'deviceLinking': 'Cihaz Bağlama',
    'serverAlreadyRegistered': 'Bu Server Zaten Kayıtlı',
    'howItWorks': 'NASIL ÇALIŞIR?',
    'sending': 'Gönderiliyor…',
    'sendConnectionRequest': 'Bağlantı İsteği Gönder',
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
    'pinsDontMatch': 'PIN\'ler eşleşmiyor. Tekrar deneyin.',
    'patternsDontMatch': 'Desenler eşleşmiyor. Tekrar deneyin.',
    // Wallpaper
    'wallpaperPreview': 'Duvar Kağıdı Önizleme',
    // Chat menu
    // GIF creator
    'gifCreate': 'GIF Oluştur',
    'scanning': 'Taranıyor…',
    'addFrame': 'Kare Ekle',
    'creating': 'Oluşturuluyor…',
    'sendGif': 'GIF Gönder',
    // Pulse AI
    'pulseAiWelcome': 'Kelime anlamı mı merak ediyorsun? Bir şey mi sormak istiyorsun? Sohbet etmek mi istiyorsun? Buradayım.',
    'pulseAiTyping': 'Pulse AI yazıyor…',
    'pulseAiHint': 'Pulse AI\'e bir şey sor…',
    // QR
    'qrHoldCode': 'Arkadaşının QR kodunu kameraya tut',
    'qrHoldGroupCode': 'Grup davet QR kodunu kameraya tut',
    'scanQr': 'QR Tara',
    'groupInviteQr': 'Grup Davet QR\'ı',
    'scanGroupQr': 'Grup QR\'ını Tara',
    // Contacts
    'deactivateWarn': 'Hayır derseniz kendi sunucunuzdaki sohbet geçmişleri silinir.',
    'noDestroy': 'Hayır, imha et',
    'emptyContacts': 'Rehberin boş',
    'giveUp': 'Vazgeç',
    // Settings deep
    'quickRepliesTitle': 'Hızlı Yanıtlar',
    'noQuickReplyYet': 'Henüz hızlı yanıt eklenmemiş.',
    'newQuickReply': 'Yeni Hızlı Yanıt',
    'writeMessageHint': 'Mesaj yazın...',
    'iptalUp': 'İptal',
    'statusMsgHint': 'Müsait, Meşgul, Toplantıda…',
    'bioHint': 'Kendin hakkında kısa bir şeyler yaz…',
    'lockProtected': 'PIN veya desen ile korunuyor',
    'lockOff': 'Kapalı',
    'change': 'Değiştir',
    'setUp': 'Ayarla',
    'smallSize': 'Küçük',
    'bigSize': 'Büyük',
    'preview': 'ÖNIZLEME',
    'previewMessage': 'Mesajlarınız bu boyutta görünür.',
    'voiceGender': 'SES CİNSİYETİ',
    'voiceGenderDesc': 'TTS sesli mesaj için ses tonu',
    'female': 'Kadın',
    'starredMessagesLabel': 'Yıldızlı Mesajlar',
    'sttTitle': 'Sesli Mesaj (STT)',
    'sttDesc': 'Konuşarak mesaj yaz. "Gönder" diyince otomatik gönderir. Mikrofon izni gerekir.',
    'chatWallpaperTitle': 'Sohbet Duvar Kâğıdı',
    'wallpaperTypeDefault': 'Varsayılan',
    'wallpaperTypeColor': 'Renk',
    'wallpaperTypeImage': 'Resim',
    'notifSoundTitle': 'Bildirim Sesi',
    'pickNotifSound': 'Bildirim Sesi Seç',
    'pulseAiTitle': 'Pulse AI',
    'myStory': 'Hikayem',
    'kodum': 'KODUM',
    'male': 'Erkek',
    'language_tr': 'Türkçe',
    'language_en': 'İngilizce',
    'language_de': 'Almanca',
    'language_fr': 'Fransızca',
    'language_es': 'İspanyolca',
    'language_it': 'İtalyanca',
    'language_pt': 'Portekizce',
    'language_ru': 'Rusça',
    'language_ar': 'Arapça',
    'language_zh': 'Çince',
    'language_ja': 'Japonca',
    'language_ko': 'Korece',
    // v10.2.0 — strings that were previously hardcoded in Turkish
    'translateStarting': 'Çeviri başlıyor…',
    'msgEmpty': 'Boş mesaj gönderilemez.',
    'msgTooLong': 'Mesaj en fazla {n} karakter olabilir.',
    'msgNoLinks': 'Bağlantı veya görsel gönderemezsiniz.',
    'gifMaxFrames': 'En fazla 8 kare eklenebilir',
    'gifNeedFrame': 'En az 1 kare gerekli',
    'gifFrameNsfw': '⛔ Bu görsel uygunsuz içerik taşıyor — eklenemez.',
    'gifCaptionNsfw': '⛔ Başlık uygunsuz içerik taşıyor — düzelt.',
    'gifNsfwBlocked': '⛔ Uygunsuz içerik tespit edildi — GIF oluşturulmadı.',
    'gifEncodeFailed': 'GIF oluşturulurken hata',
    'roleOwner': 'Sahip',
    'roleMember': 'Üye',
    'emptyContactsHint': 'Arkadaşının 5 haneli kodunu girerek kişi ekle.',
    'blockUser': 'kullanıcısını engelle',
    'invitePendingApproval': 'Davet gönderildi · onay bekleniyor',
    'networkError': 'Ağ hatası',
    'aiNoReply': 'Yanıt alınamadı.',
    'aiGenericError': 'Bir hata oluştu.',
    'aiUnreachable': 'Pulse AI\'e ulaşılamadı. Sunucu bağlantını kontrol et.',
    'notifNewMessageTitle': 'Yeni mesaj',
    'notifNewMessageBodySuffix': 'size mesaj attı',
    'messageDeleted': 'Bu mesaj silindi.',
    'editedLabel': 'düzenlendi',
    'forwardToWhom': 'Kime ilet?',
    'friendAddedSuffix': 'arkadaş listene eklendi.',
    'blockedSuffix': 'engellendi.',
    'inviteSentSuffix': 'kullanıcısına davet gönderildi.',
    'groupCreatedPrefix': 'Grup oluşturuldu',
    'joinRequestSentSuffix': 'grubuna katılma isteği gönderildi.',
    'whatAreYouThinking': 'Ne düşünüyorsun?',
    'codeCopiedPrefix': 'Kodun kopyalandı',
    'gifFramesEmpty': 'Galeriden fotoğraf ekle\n(en fazla 8 kare)',
    'gifCaptionHint': 'Başlık (isteğe bağlı)',
    'acceptFailedShort': 'Kabul edilemedi.',
    'rejectFailedShort': 'Reddedilemedi.',
    'mutedTitle': 'Susturuldunuz',
    'mutedBodySuffix': 'grubunda susturuldunuz',
    'mutedUserSuffix': 'susturuldu.',
    'ownerLabel': '(sahip)',
    'announcementHint': 'Duyuru metni…',
    'nsfwBlocked': 'Uygunsuz içerik tespit edildi — paylaşılmadı.',
    'updateAvailable': 'Güncelleme Mevcut',
    'updateNow': 'Güncelle',
    'updateLater': 'Sonra',
    'updateDownload': 'İndir',
    'updateDownloading': '%{p} indiriliyor…',
    'updatePreparing': 'Hazırlanıyor…',
    'updateFailed': 'İndirme başarısız. Tarayıcıdan güncelle.',
    'defaultSound': 'Varsayılan',
    'silent': 'Sessiz',
    'starredMessagesSubtitle': 'Yıldızladığın mesajları gör',
    'back': 'Geri',
    'justCopy': 'Kopyala',
    'createStory': 'Hikaye Oluştur',
    'backgroundColor': 'Arka plan rengi',
    'storyNotFound': 'Hikaye bulunamadı',
    'imageLoadFailedShort': 'Görsel yüklenemedi',
    'cannotJoinOwnGroup': 'Bu grup zaten senin. Kendi grubuna katılamazsın.',
    'alreadyInGroup': 'Bu gruba zaten katıldın.',
    'mediumSize': 'Orta',
    'deviceManagementSubtitle': 'Yan cihazlar, fake hesaplar ve bağlantı istekleri',
    'translationPreparing': 'Çeviri hazırlanıyor…',
    'translationFailed': 'Çeviri başarısız — internet bağlantısını kontrol et.',
    'keepChatsQuestion': 'Sohbetler kaydedilsin mi?',
    'yesKeep': 'Evet, sakla',
    'invites': 'Davetler',
    'manageFrequentMessages': 'Sık kullanılan mesajları yönet',
    'yourAddressLabel': 'SENİN ADRESİN',
    'thisDeviceFipBlock': 'BU CİHAZIN FIP BLOĞU',
    'deviceSounds': 'CİHAZ SESLERİ',
    'deactivateAccountTitle': 'Hesabı bu cihazdan kaldır',
    'deactivateAccountBody': 'FIP bloğun, kişi listen ve aktif sohbetlerin kalıcı olarak silinir.',
    'deleteAccountButton': 'Hesabı sil',
    'yesDelete': 'Evet, sil',
    'avatarNsfwRejected': '⛔ Bu görsel uygunsuz içerik taşıyor — avatar olarak ayarlanamaz.',
    // --- Dükkan / VIP katmanları. Katman adları (VIP, PhotonPulseVİP …) marka
    // oldukları için çevrilmez; yalnızca açıklamalar çevrilir.
    'vipNone': 'Katmanın yok',
    'vipAddsColoredName': 'Renkli ad',
    'vipAddsColoredText': 'Renkli mesaj yazısı',
    'vipAddsBold': 'Kalın mesaj yazabilme',
    'vipAddsTag': 'PREMIUM rozeti',
    'vipAddsBigFiles': '30MB daha büyük dosya',
    'vipAddsRender': 'Daha kaliteli görsel (1440p)',
    'vipAddsEncryption': 'Ekstra güvenlik — cihaz verisi şifreleme',
    'vipAddsFakeName': 'Fake isim',
    'shopTitle': 'Dükkan',
    'shopCurrentTier': 'Şu anki katmanın',
    'shopActive': 'Aktif',
    'shopPerMonth': '/ay',
    'shopBuy': 'Satın Al',
    'shopOutOfService': 'Hizmet Dışıdır.',
    'shopAllFeatures': 'Bu katmanla gelenler',
    'shopColorSection': 'RENGİN',
    'shopColorSaved': 'Renk kaydedildi.',
    'shopColorFailed': 'Renk kaydedilemedi.',
    'boldHint': 'Kalın yazmak için: /k kalın kısım /t',
    'fakeNameTitle': 'Fake İsim',
    'fakeNameSubtitle': 'Takma adınla görün',
    'fakeNameField': 'Fake isim',
    'fakeNameHint': 'Örn: Anonim',
    'fakeNameEnabled': 'Fake isim aktif',
    'fakeNameShowing': 'Şu an görünen',
    'fakeNameSaved': 'Kaydedildi.',
    'fakeNameFailed': 'Kaydedilemedi.',
    'fakeNameEmpty': 'Önce bir fake isim yaz.',
    'vipLocked': 'Bu özellik için üst katman gerekir',
    // Geçici test kodu bölümü — ödeme bağlanınca kaldırılacak.
    'shopRedeemTitle': 'Kod Kullan',
    'shopRedeemHint': 'Kod',
    'shopRedeemButton': 'Kullan',
    'shopRedeemOk': 'Kod kabul edildi — test modu açık.',
    'shopRedeemBad': 'Geçersiz kod.',
    'shopOwnerMode': 'TEST MODU AÇIK',
    'shopOwnerModeDesc': 'Katmanları ödeme olmadan deneyebilirsin.',
    'shopGranted': 'Katman verildi.',
    'shopGrantFailed': 'Katman verilemedi.',
    'shopRevoke': 'Katmanı kaldır',
  };
}
