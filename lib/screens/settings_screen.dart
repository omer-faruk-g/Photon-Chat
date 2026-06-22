import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../onboarding_screen.dart';
import '../theme.dart';
import '../chat_wallpaper.dart';
import '../nsfw_scanner.dart';
import 'wallpaper_screen.dart';
import '../i18n.dart';

class SettingsScreen extends StatefulWidget {
  final FipBlock identity;
  final String myServerUrl;
  final String displayName;
  const SettingsScreen({super.key, required this.identity, required this.myServerUrl, required this.displayName});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirming = false;
  bool _deleting = false;
  String _avatar = '';
  String _statusMsg = '';
  final _statusCtrl = TextEditingController();
  bool _savingStatus = false;
  bool _sttEnabled = false;

  @override
  void initState() {
    super.initState();
    LocalStore.loadSttEnabled().then((v) { if (mounted) setState(() => _sttEnabled = v); });
    _load();
  }

  @override
  void dispose() {
    _statusCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final avatar = await LocalStore.loadAvatar();
    final statusMsg = await LocalStore.loadStatusMsg();
    setState(() {
      _avatar = avatar;
      _statusMsg = statusMsg;
      _statusCtrl.text = statusMsg;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 40, maxWidth: 128, maxHeight: 128);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    // Avatar NSFW taraması
    final isNsfw = await NsfwScanner.hasImageViolation(bytes);
    if (isNsfw) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⛔ Bu görsel uygunsuz içerik taşıyor — avatar olarak ayarlanamaz.'),
            backgroundColor: KnkColors.danger,
          ),
        );
      }
      return;
    }

    if (bytes.length > 200 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fotoğraf çok büyük (max 200KB)')));
      return;
    }
    final b64 = base64Encode(bytes);
    await LocalStore.saveAvatar(b64);
    setState(() => _avatar = b64);
    await _syncPresence();
  }

  Future<void> _saveStatus() async {
    setState(() => _savingStatus = true);
    final msg = _statusCtrl.text.trim();
    await LocalStore.saveStatusMsg(msg);
    setState(() { _statusMsg = msg; _savingStatus = false; });
    await _syncPresence();
  }

  Future<void> _syncPresence() async {
    await KnkApi.registerPresence(
      widget.myServerUrl,
      widget.identity.fipId,
      widget.identity.code,
      widget.displayName,
      statusMsg: _statusMsg,
      avatar: _avatar,
    );
  }

  Future<void> _deactivate() async {
    setState(() => _deleting = true);
    await KnkApi.deactivate(widget.myServerUrl, widget.identity.fipId);
    await LocalStore.wipeIdentity();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Widget _buildWallpaperPreview() {
    if (ChatWallpaper.type == 'color' && ChatWallpaper.value.isNotEmpty) {
      return Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: Color(int.parse(ChatWallpaper.value, radix: 16)),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: KnkColors.line),
        ),
      );
    }
    if (ChatWallpaper.type == 'image' && ChatWallpaper.value.isNotEmpty) {
      try {
        final bytes = base64Decode(ChatWallpaper.value);
        return Container(
          width: 28, height: 28,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: KnkColors.line)),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }

  Widget _buildAvatar() {
    if (_avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(_avatar);
        return CircleAvatar(radius: 36, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    final name = widget.displayName;
    return CircleAvatar(
      radius: 36,
      backgroundColor: KnkColors.accent.withOpacity(0.2),
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: KnkColors.accent, fontSize: 28, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildLangChip(String code, String label) {
    final isActive = AppLang.instance.lang == code;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          AppLang.instance.setLang(code);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? KnkColors.accent : KnkColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? KnkColors.accent : KnkColors.line),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            textDirection: code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(
              color: isActive ? const Color(0xFF06251A) : KnkColors.text,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _openLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: KnkColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLang.instance.t('selectLanguage'), style: TextStyle(color: KnkColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              Divider(color: KnkColors.line, height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: AppLang.supportedLanguages.length,
                  itemBuilder: (ctx, i) {
                    final lang = AppLang.supportedLanguages[i];
                    final isActive = AppLang.instance.lang == lang['code'];
                    return ListTile(
                      leading: Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                      title: Text(lang['name']!, style: TextStyle(color: KnkColors.text, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                      trailing: isActive ? Icon(Icons.check_circle, color: KnkColors.accent, size: 20) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        AppLang.instance.setLang(lang['code']!);
                        setState(() {});
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myAddress = '${widget.identity.code}@${widget.myServerUrl}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profil fotoğrafı
          Center(
            child: Stack(children: [
              _buildAvatar(),
              Positioned(
                bottom: 0, right: 0,
                child: GestureDetector(
                  onTap: _pickAvatar,
                  child: Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(color: KnkColors.accent, shape: BoxShape.circle, border: Border.all(color: KnkColors.bg, width: 2)),
                    child: const Icon(Icons.camera_alt, color: Color(0xFF06251A), size: 14),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Center(child: Text(widget.displayName, style: TextStyle(color: KnkColors.text, fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(height: 20),

          // Durum mesajı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DURUM MESAJI', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _statusCtrl,
                style: TextStyle(color: KnkColors.text, fontSize: 13),
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: 'Müsait, Meşgul, Toplantıda…',
                  hintStyle: TextStyle(color: KnkColors.textDim, fontSize: 12),
                  filled: true, fillColor: KnkColors.bg,
                  counterStyle: TextStyle(color: KnkColors.textDim, fontSize: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: KnkColors.line)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: knkPrimaryButtonStyle(),
                  onPressed: _savingStatus ? null : _saveStatus,
                  child: _savingStatus ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06251A))) : const Text('Kaydet'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Tema Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(KnkTheme.instance.isDark ? Icons.dark_mode : Icons.light_mode, color: KnkColors.textDim, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Tema', style: TextStyle(color: KnkColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                Text(KnkTheme.instance.isDark ? 'Karanlık mod' : 'Aydınlık mod', style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
              ])),
              Switch(
                value: KnkTheme.instance.isDark,
                onChanged: (v) async {
                  KnkTheme.instance.setDark(v);
                  await LocalStore.saveThemeDark(v);
                  setState(() {});
                },
                activeColor: KnkColors.accent,
              ),
            ]),
          ),
          const SizedBox(height: 16),

          const SizedBox(height: 12),
          // Sesli Mesaj (STT)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.mic, color: KnkColors.textDim, size: 18),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sesli Mesaj (STT)', style: TextStyle(color: KnkColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Konuşarak mesaj yaz. "Gönder" diyince otomatik gönderir. Mikrofon izni gerekir.', style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.5)),
              ])),
              Switch(
                value: _sttEnabled,
                onChanged: (v) async {
                  await LocalStore.saveSttEnabled(v);
                  setState(() => _sttEnabled = v);
                },
                activeColor: KnkColors.accent,
              ),
            ]),
          ),

          // Sohbet Duvar Kağıdı
          GestureDetector(
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPickerScreen()));
              await ChatWallpaper.loadWallpaper();
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(Icons.wallpaper, color: KnkColors.textDim, size: 18),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sohbet Duvar Kagidi', style: TextStyle(color: KnkColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(
                    ChatWallpaper.type == 'none' ? 'Varsayilan' : ChatWallpaper.type == 'color' ? 'Renk' : 'Resim',
                    style: TextStyle(color: KnkColors.textDim, fontSize: 11),
                  ),
                ])),
                _buildWallpaperPreview(),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: KnkColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Dil Seçimi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.language, color: KnkColors.textDim, size: 18),
                const SizedBox(width: 12),
                Text(AppLang.instance.t('language'), style: TextStyle(color: KnkColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _buildLangChip('tr', '🇹🇷 Türkçe'),
                const SizedBox(width: 8),
                _buildLangChip('en', '🇬🇧 English'),
                const SizedBox(width: 8),
                _buildLangChip('ar', '🇸🇦 العربية'),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: KnkColors.accent,
                    side: BorderSide(color: KnkColors.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.translate, size: 16, color: KnkColors.accent),
                  label: Text('${AppLang.supportedLanguages.length} ${AppLang.instance.t('language')}', style: TextStyle(fontSize: 12)),
                  onPressed: _openLanguagePicker,
                ),
              ),
              if (AppLang.instance.translatingUi)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.accent)),
                    const SizedBox(width: 8),
                    Text(AppLang.instance.t('translating'), style: TextStyle(color: KnkColors.textDim, fontSize: 11)),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // Adres
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.accent.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SENİN ADRESİN', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(myAddress, style: TextStyle(color: KnkColors.accent, fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: KnkColors.text, side: BorderSide(color: KnkColors.line), padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Kodunu Kopyala', style: TextStyle(fontSize: 13)),
                  onPressed: () => Clipboard.setData(ClipboardData(text: widget.identity.code)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FipCard(title: 'BU CİHAZIN FIP BLOĞU', fip: widget.identity),
          const SizedBox(height: 20),

          // Hesap silme
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1A1314), border: Border.all(color: KnkColors.danger.withOpacity(0.27)), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hesabı bu cihazdan kaldır', style: TextStyle(color: KnkColors.danger, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              Text('FIP bloğun, kişi listen ve aktif sohbetlerin kalıcı olarak silinir.', style: TextStyle(color: KnkColors.textDim, fontSize: 11.5, height: 1.6)),
              const SizedBox(height: 14),
              if (!_confirming)
                ElevatedButton(
                  style: knkDangerButtonStyle(),
                  onPressed: () => setState(() => _confirming = true),
                  child: const SizedBox(width: double.infinity, child: Text('Hesabı sil', textAlign: TextAlign.center)),
                )
              else
                Row(children: [
                  Expanded(child: OutlinedButton(style: knkGhostButtonStyle(), onPressed: _deleting ? null : () => setState(() => _confirming = false), child: const Text('Vazgeç'))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(
                    style: knkDangerButtonStyle(),
                    onPressed: _deleting ? null : _deactivate,
                    child: _deleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Evet, sil'),
                  )),
                ]),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: knkGhostButtonStyle(),
            onPressed: () => Navigator.pop(context),
            child: const SizedBox(width: double.infinity, child: Text('Geri', textAlign: TextAlign.center)),
          ),
        ],
      ),
    );
  }
}
