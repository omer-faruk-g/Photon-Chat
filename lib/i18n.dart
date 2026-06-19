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
  };
}
