import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../fip.dart';
import '../photon_api.dart';
import '../local_store.dart';
import '../onboarding_screen.dart';
import '../theme.dart';
import '../chat_wallpaper.dart';
import '../nsfw_scanner.dart';
import 'wallpaper_screen.dart';
import 'devices_screen.dart';
import 'starred_messages_screen.dart';
import '../i18n.dart';
import '../sound_picker.dart';
import '../quick_replies.dart';
import '../app_lock.dart';
import 'lock_screen.dart';
import '../font_size.dart';
import '../vip.dart';
import 'fake_name_screen.dart';
import 'profile_anim_screen.dart';
import 'shop_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  String _bio = '';
  final _bioCtrl = TextEditingController();
  bool _savingBio = false;
  String _voiceGender = 'male';
  // Stored as the literal sentinels 'Varsayilan' / 'Sessiz', or a device
  // ringtone's own name. The sentinels are identifiers, not display text — they
  // stayed Turkish on every other language until they were mapped through i18n
  // at render time. Ringtone names come from the OS and are shown verbatim.
  String _notifSound = 'Varsayilan';
  String get _notifSoundLabel {
    if (_notifSound == 'Varsayilan') return AppLang.instance.t('defaultSound');
    if (_notifSound == 'Sessiz') return AppLang.instance.t('silent');
    return _notifSound;
  }
  String _fontSize = 'orta';
  bool _lockEnabled = false;
  VipStatus _vip = VipStatus.none;

  @override
  void initState() {
    super.initState();
    LocalStore.loadSttEnabled().then((v) { if (mounted) setState(() => _sttEnabled = v); });
    LocalStore.loadBio().then((v) { if (mounted) setState(() { _bio = v; _bioCtrl.text = v; }); });
    LocalStore.loadVoiceGender().then((v) { if (mounted) setState(() => _voiceGender = v); });
    LocalStore.loadNotifSound().then((v) { if (mounted) setState(() => _notifSound = v); });
    LocalStore.loadFontSize().then((v) { if (mounted) setState(() => _fontSize = v); });
    AppLock.isEnabled().then((v) { if (mounted) setState(() => _lockEnabled = v); });
    PhotonApi.getTier(widget.identity.fipId).then((raw) {
      if (mounted && raw != null) setState(() => _vip = VipStatus.fromJson(raw));
    });
    _load();
  }

  @override
  void dispose() {
    _statusCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final avatar = await LocalStore.loadAvatar();
    final statusMsg = await LocalStore.loadStatusMsg();
    if (!mounted) return;
    setState(() {
      _avatar = avatar;
      _statusMsg = statusMsg;
      _statusCtrl.text = statusMsg;
    });
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 512, maxHeight: 512);
    if (file == null) return;
    final bytes = await file.readAsBytes();

    // Avatar NSFW taraması
    final isNsfw = await NsfwScanner.hasImageViolation(bytes);
    if (isNsfw) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLang.instance.t('avatarNsfwRejected')),
            backgroundColor: PhotonColors.danger,
          ),
        );
      }
      return;
    }

    if (bytes.length > 300 * 1024) { // v9.2: bumped for HD avatars
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLang.instance.t('photoTooLarge'))));
      return;
    }
    final b64 = base64Encode(bytes);
    await LocalStore.saveAvatar(b64);
    if (!mounted) return;
    setState(() => _avatar = b64);
    await _syncPresence();
  }

  Future<void> _saveStatus() async {
    setState(() => _savingStatus = true);
    final msg = _statusCtrl.text.trim();
    await LocalStore.saveStatusMsg(msg);
    if (!mounted) return;
    setState(() { _statusMsg = msg; _savingStatus = false; });
    await _syncPresence();
  }

  Future<void> _saveBio() async {
    setState(() => _savingBio = true);
    final bio = _bioCtrl.text.trim();
    await LocalStore.saveBio(bio);
    if (!mounted) return;
    setState(() { _bio = bio; _savingBio = false; });
  }

  Future<void> _openQuickRepliesDialog() async {
    List<String> replies = await QuickReplies.load();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlgState) {
        return AlertDialog(
          backgroundColor: PhotonColors.panel,
          title: Text(AppLang.instance.t('quickRepliesTitle'), style: TextStyle(color: PhotonColors.text, fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (replies.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(AppLang.instance.t('noQuickReplyYet'), style: PText.small),
                )
              else
                ...replies.map((r) => ListTile(
                  dense: true,
                  title: Text(r, style: TextStyle(color: PhotonColors.text, fontSize: 13)),
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline, color: PhotonColors.danger, size: 18),
                    onPressed: () async {
                      await QuickReplies.remove(r);
                      replies = await QuickReplies.load();
                      setDlgState(() {});
                    },
                  ),
                )),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLang.instance.t('close'), style: TextStyle(color: PhotonColors.textDim)),
            ),
            TextButton(
              onPressed: () async {
                final ctrl = TextEditingController();
                final result = await showDialog<String>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    backgroundColor: PhotonColors.panel,
                    title: Text(AppLang.instance.t('newQuickReply'), style: TextStyle(color: PhotonColors.text, fontSize: 15)),
                    content: TextField(
                      controller: ctrl,
                      style: TextStyle(color: PhotonColors.text),
                      decoration: InputDecoration(hintText: AppLang.instance.t('writeMessageHint'), hintStyle: TextStyle(color: PhotonColors.textDim)),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c), child: Text(AppLang.instance.t('iptalUp'), style: TextStyle(color: PhotonColors.textDim))),
                      TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: Text(AppLang.instance.t('add'), style: TextStyle(color: PhotonColors.accent))),
                    ],
                  ),
                );
                ctrl.dispose();
                if (result != null && result.isNotEmpty) {
                  await QuickReplies.add(result);
                  replies = await QuickReplies.load();
                  setDlgState(() {});
                }
              },
              child: Text(AppLang.instance.t('add'), style: TextStyle(color: PhotonColors.accent)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _openSoundPicker() async {
    final sounds = await SoundPicker.getNotificationSounds();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            Icon(Icons.notifications_active_outlined, color: PhotonColors.accent, size: 20),
            const SizedBox(width: 8),
            Text(AppLang.instance.t('pickNotifSound'), style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            GestureDetector(
              onTap: () { SoundPicker.stopSound(); Navigator.pop(ctx); },
              child: Icon(Icons.close_outlined, color: PhotonColors.textDim, size: 20),
            ),
          ])),
          Divider(color: PhotonColors.line, height: 1),
          // Varsayilan + Sessiz
          ListTile(
            leading: Icon('Varsayilan' == _notifSound ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: PhotonColors.accent),
            title: Text(AppLang.instance.t('defaultSound'), style: TextStyle(color: PhotonColors.text)),
            onTap: () async {
              SoundPicker.stopSound();
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('knk_notif_sound_v1', 'Varsayilan');
              await prefs.setString('knk_notif_sound_uri_v1', 'default');
              setState(() => _notifSound = 'Varsayilan');
            },
          ),
          ListTile(
            leading: Icon('Sessiz' == _notifSound ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: PhotonColors.accent),
            title: Text(AppLang.instance.t('silent'), style: TextStyle(color: PhotonColors.text)),
            onTap: () async {
              SoundPicker.stopSound();
              Navigator.pop(ctx);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('knk_notif_sound_v1', 'Sessiz');
              await prefs.setString('knk_notif_sound_uri_v1', 'silent');
              setState(() => _notifSound = 'Sessiz');
            },
          ),
          Divider(color: PhotonColors.line, height: 1),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(AppLang.instance.t('deviceSounds'), style: PText.label)),
          Expanded(
            child: ListView.builder(
              controller: scrollCtrl,
              itemCount: sounds.length,
              itemBuilder: (_, i) {
                final s = sounds[i];
                final isSelected = _notifSound == s['title'];
                return ListTile(
                  leading: Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: PhotonColors.accent),
                  title: Text(s['title'] ?? '', style: TextStyle(color: PhotonColors.text, fontSize: 13)),
                  trailing: IconButton(
                    icon: Icon(Icons.play_circle_outline, color: PhotonColors.accent, size: 22),
                    onPressed: () => SoundPicker.playSound(s['uri'] ?? ''),
                  ),
                  onTap: () async {
                    SoundPicker.stopSound();
                    Navigator.pop(ctx);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('knk_notif_sound_v1', s['title'] ?? 'Varsayilan');
                    await prefs.setString('knk_notif_sound_uri_v1', s['uri'] ?? 'default');
                    setState(() => _notifSound = s['title'] ?? 'Varsayilan');
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
    // Ensure any preview sound is stopped on any dismissal path
    // (back button, tap outside, drag down).
    await SoundPicker.stopSound();
  }

  Future<void> _syncPresence() async {
    await PhotonApi.registerPresence(
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
    await PhotonApi.deactivate(widget.myServerUrl, widget.identity.fipId);
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
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PhotonColors.line),
        ),
      );
    }
    if (ChatWallpaper.type == 'image' && ChatWallpaper.value.isNotEmpty) {
      try {
        final bytes = base64Decode(ChatWallpaper.value);
        return Container(
          width: 28, height: 28,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: PhotonColors.line)),
          clipBehavior: Clip.antiAlias,
          child: Image.memory(bytes, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    return const SizedBox.shrink();
  }

  Widget _buildAvatar() {
    const size = Space.s7 - Space.s3; // 72
    if (_avatar.isNotEmpty) {
      try {
        final bytes = base64Decode(_avatar);
        return ClipRRect(
          borderRadius: BorderRadius.circular(size / 4),
          child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {}
    }
    final name = widget.displayName;
    return Container(
      width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PhotonColors.accentWash,
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: PhotonColors.line),
      ),
      child: Text(name.isNotEmpty ? trUpper(name[0]) : '?',
          style: TextStyle(fontFamily: PhotonFonts.display, color: PhotonColors.accent, fontSize: 32)),
    );
  }

  Widget _buildFontSizeChip(String value, String label) {
    final isActive = _fontSize == value;
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          await FontSizeNotifier.instance.setSize(value);
          setState(() => _fontSize = value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? PhotonColors.accent : PhotonColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? PhotonColors.accent : PhotonColors.line),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? PhotonColors.onAccent : PhotonColors.text,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _switchLang(String code) async {
    if (AppLang.instance.lang == code) return;
    // Open a modal that listens to AppLang so it shows live progress.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AnimatedBuilder(
        animation: AppLang.instance,
        builder: (_, __) {
          final progress = AppLang.instance.translateProgress;
          return Dialog(
            backgroundColor: PhotonColors.panel,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: PhotonColors.accent, value: progress > 0 ? progress : null),
                const SizedBox(height: 16),
                Text(AppLang.instance.t('language'), style: TextStyle(color: PhotonColors.text, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  AppLang.instance.translateStatus.isNotEmpty
                    ? AppLang.instance.translateStatus
                    : (progress > 0 ? '${(progress * 100).toInt()}%' : AppLang.instance.t('translationPreparing')),
                  style: PText.small,
                  textAlign: TextAlign.center,
                ),
              ]),
            ),
          );
        },
      ),
    );
    final ok = await AppLang.instance.setLang(code);
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLang.instance.t('translationFailed')),
        backgroundColor: PhotonColors.danger,
      ));
    }
    if (mounted) setState(() {});
  }

  Widget _buildLangChip(String code, String label) {
    final isActive = AppLang.instance.lang == code;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchLang(code),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? PhotonColors.accent : PhotonColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isActive ? PhotonColors.accent : PhotonColors.line),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            textDirection: code == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            style: TextStyle(
              color: isActive ? PhotonColors.onAccent : PhotonColors.text,
              fontSize: 13,
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
      backgroundColor: PhotonColors.panel,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return Container(
          constraints: const BoxConstraints(maxHeight: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(AppLang.instance.t('selectLanguage'), style: TextStyle(color: PhotonColors.text, fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              Divider(color: PhotonColors.line, height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: AppLang.supportedLanguages.length,
                  itemBuilder: (ctx, i) {
                    final lang = AppLang.supportedLanguages[i];
                    final isActive = AppLang.instance.lang == lang['code'];
                    return ListTile(
                      leading: Text(lang['flag']!, style: const TextStyle(fontSize: 26)),
                      title: Text(AppLang.instance.languageLabel(lang['code']!, lang['name']!),
                          style: TextStyle(color: PhotonColors.text, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                      trailing: isActive ? Icon(Icons.check_circle, color: PhotonColors.accent, size: 20) : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchLang(lang['code']!);
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
      appBar: AppBar(title: Text(AppLang.instance.t('settings'))),
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
                    decoration: BoxDecoration(color: PhotonColors.accent, shape: BoxShape.circle, border: Border.all(color: PhotonColors.bg, width: 2)),
                    child: Icon(Icons.camera_alt_outlined, color: PhotonColors.onAccent, size: 14),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Center(child: Text(widget.displayName, style: PText.h2)),
          const SizedBox(height: 16),

          // Durum mesajı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLang.instance.t('statusMessage'), style: PText.label),
              const SizedBox(height: 8),
              TextField(
                controller: _statusCtrl,
                style: PText.body,
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: AppLang.instance.t('statusMsgHint'),
                  hintStyle: PText.small,
                  filled: true, fillColor: PhotonColors.bg,
                  counterStyle: PText.meta,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _savingStatus ? null : _saveStatus,
                  child: _savingStatus ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.accent)) : Text(AppLang.instance.t('save')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Bio
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLang.instance.t('bioSection'), style: PText.label),
              const SizedBox(height: 8),
              Focus(
                onFocusChange: (hasFocus) { if (!hasFocus) _saveBio(); },
                child: TextField(
                  controller: _bioCtrl,
                  style: PText.body,
                  maxLength: 100,
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: AppLang.instance.t('bioHint'),
                    hintStyle: PText.small,
                    filled: true, fillColor: PhotonColors.bg,
                    counterText: '${_bioCtrl.text.length}/100',
                    counterStyle: PText.meta,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: PhotonColors.line)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: _savingBio ? null : _saveBio,
                  child: _savingBio ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.accent)) : Text(AppLang.instance.t('save')),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Tema Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Row(children: [
              Icon(PhotonTheme.instance.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: PhotonColors.textDim, size: 18),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLang.instance.t('themeSection'), style: PText.title),
                Text(PhotonTheme.instance.isDark ? AppLang.instance.t('darkMode') : AppLang.instance.t('lightMode'), style: PText.meta),
              ])),
              Switch(
                value: PhotonTheme.instance.isDark,
                onChanged: (v) async {
                  PhotonTheme.instance.setDark(v);
                  await LocalStore.saveThemeDark(v);
                  setState(() {});
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Uygulama Kilidi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Row(children: [
              Icon(Icons.lock_outline, color: PhotonColors.textDim, size: 18),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLang.instance.t('appLockSection'), style: PText.title),
                Text(_lockEnabled ? AppLang.instance.t('lockProtected') : AppLang.instance.t('lockOff'), style: PText.meta),
              ])),
              if (_lockEnabled)
                GestureDetector(
                  onTap: () async {
                    await AppLock.disable();
                    if (!mounted) return;
                    setState(() => _lockEnabled = false);
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(AppLang.instance.t('remove'), style: TextStyle(color: PhotonColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
              GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => SetLockScreen(onDone: () {
                    setState(() => _lockEnabled = true);
                  })));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
                  decoration: BoxDecoration(color: PhotonColors.accentWash, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
                  child: Text(_lockEnabled ? AppLang.instance.t('change') : AppLang.instance.t('setUp'), style: PText.small.copyWith(color: PhotonColors.accent, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Yazı Boyutu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLang.instance.t('fontSizeSection'), style: PText.label),
              const SizedBox(height: 8),
              Row(children: [
                _buildFontSizeChip('kucuk', AppLang.instance.t('smallSize')),
                const SizedBox(width: 8),
                _buildFontSizeChip('orta', AppLang.instance.t('mediumSize')),
                const SizedBox(width: 8),
                _buildFontSizeChip('buyuk', AppLang.instance.t('bigSize')),
              ]),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: PhotonColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: PhotonColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('preview'), style: PText.label),
                  const SizedBox(height: 8),
                  Text(
                    AppLang.instance.t('previewMessage'),
                    style: TextStyle(color: PhotonColors.text, fontSize: FontSizeNotifier.instance.msgFontSize, height: 1.4),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Sesli Mesaj (STT)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Row(children: [
              Icon(Icons.mic_outlined, color: PhotonColors.textDim, size: 18),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLang.instance.t('sttTitle'), style: PText.title),
                Text(AppLang.instance.t('sttDesc'), style: PText.meta),
              ])),
              Switch(
                value: _sttEnabled,
                onChanged: (v) async {
                  await LocalStore.saveSttEnabled(v);
                  setState(() => _sttEnabled = v);
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),
          // Ses Cinsiyeti
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Row(children: [
              Icon(Icons.record_voice_over_outlined, color: PhotonColors.textDim, size: 18),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(AppLang.instance.t('voiceGender'), style: PText.title),
                Text(AppLang.instance.t('voiceGenderDesc'), style: PText.meta),
              ])),
              DropdownButton<String>(
                value: _voiceGender,
                dropdownColor: PhotonColors.panel,
                underline: const SizedBox(),
                style: TextStyle(color: PhotonColors.text, fontSize: 13),
                items: [
                  DropdownMenuItem(value: 'male', child: Text(AppLang.instance.t('male'), style: TextStyle(color: PhotonColors.text))),
                  DropdownMenuItem(value: 'female', child: Text(AppLang.instance.t('female'), style: TextStyle(color: PhotonColors.text))),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  await LocalStore.saveVoiceGender(v);
                  setState(() => _voiceGender = v);
                },
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Cihaz Yönetimi
          HoverCard(padding: EdgeInsets.zero, borderColor: PhotonColors.accent.withOpacity(0.3), 
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DevicesScreen(identity: widget.identity, myServerUrl: widget.myServerUrl))),
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.devices_outlined, color: PhotonColors.accent, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('deviceManagement'), style: PText.title),
                  Text(AppLang.instance.t('deviceManagementSubtitle'), style: PText.meta),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Fake İsim — photonPulseVip perk. Locked rows route to the shop
          // rather than doing nothing, so the upsell is discoverable.
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => _vip.effectiveTier.fakeName
                    ? FakeNameScreen(
                        fipId: widget.identity.fipId,
                        realName: widget.displayName,
                      )
                    : ShopScreen(fipId: widget.identity.fipId),
              ));
              // Reload after either screen: buying the tier here has to unlock
              // the row on the way back, not on the next visit to settings.
              final raw = await PhotonApi.getTier(widget.identity.fipId);
              if (mounted && raw != null) {
                setState(() => _vip = VipStatus.fromJson(raw));
              }
            },
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(_vip.effectiveTier.fakeName ? Icons.theater_comedy_outlined : Icons.lock_outline,
                    color: _vip.effectiveTier.fakeName ? PhotonColors.accent : PhotonColors.textDim, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('fakeNameTitle'), style: PText.title),
                  Text(
                    _vip.effectiveTier.fakeName
                        ? AppLang.instance.t('fakeNameSubtitle')
                        : AppLang.instance.t('vipLocked'),
                    style: PText.meta,
                  ),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Profil Animasyonu — profil açılırken oynayan efekt. Katmandan
          // bağımsız: animasyonlar tek tek satın alınır, abonelik bitse de kalır.
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(
                builder: (_) => ProfileAnimScreen(fipId: widget.identity.fipId),
              ));
              if (mounted) setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.auto_awesome_outlined, color: PhotonColors.accent, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('animSettingsRow'), style: PText.title),
                  Text(AppLang.instance.t('animSettingsRowDesc'), style: PText.meta),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Sohbet Duvar Kağıdı
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WallpaperPickerScreen()));
              await ChatWallpaper.loadWallpaper();
              if (!mounted) return;
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.wallpaper_outlined, color: PhotonColors.textDim, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('chatWallpaperTitle'), style: PText.title),
                  Text(
                    ChatWallpaper.type == 'none' ? AppLang.instance.t('wallpaperTypeDefault') : ChatWallpaper.type == 'color' ? AppLang.instance.t('wallpaperTypeColor') : AppLang.instance.t('wallpaperTypeImage'),
                    style: PText.meta,
                  ),
                ])),
                _buildWallpaperPreview(),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Yildizli Mesajlar
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredMessagesScreen())),
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.star, color: PhotonColors.accent2, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('starredMessagesLabel'), style: PText.title),
                  Text(AppLang.instance.t('starredMessagesSubtitle'), style: PText.meta),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Bildirim Sesi
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () => _openSoundPicker(),
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined, color: PhotonColors.textDim, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('notifSoundTitle'), style: PText.title),
                  Text(_notifSoundLabel, style: PText.meta),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Hızlı Yanıtlar
          HoverCard(padding: EdgeInsets.zero, 
            onTap: () => _openQuickRepliesDialog(),
            child: Container(
              padding: const EdgeInsets.all(Space.s2),
              child: Row(children: [
                Icon(Icons.flash_on_outlined, color: PhotonColors.textDim, size: 18),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(AppLang.instance.t('quickReplies'), style: PText.title),
                  Text(AppLang.instance.t('manageFrequentMessages'), style: PText.meta),
                ])),
                Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // Dil Seçimi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.line), borderRadius: BorderRadius.circular(PhotonRadius.card)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.language_outlined, color: PhotonColors.textDim, size: 18),
                const SizedBox(width: 16),
                Text(AppLang.instance.t('language'), style: PText.title),
              ]),
              const SizedBox(height: 16),
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
                    foregroundColor: PhotonColors.accent,
                    side: BorderSide(color: PhotonColors.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.translate_outlined, size: 16, color: PhotonColors.accent),
                  label: Text('${AppLang.supportedLanguages.length} ${AppLang.instance.t('language')}', style: TextStyle(fontSize: 13)),
                  onPressed: _openLanguagePicker,
                ),
              ),
              if (AppLang.instance.translatingUi)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: PhotonColors.accent)),
                    const SizedBox(width: 8),
                    Text(AppLang.instance.t('translating'), style: PText.meta),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // Adres
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhotonColors.panel, border: Border.all(color: PhotonColors.accent.withOpacity(0.3)), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLang.instance.t('yourAddressLabel'), style: PText.label),
              const SizedBox(height: 8),
              Text(myAddress, style: TextStyle(color: PhotonColors.accent, fontSize: 13, fontFamily: PhotonFonts.body, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: PhotonColors.text, side: BorderSide(color: PhotonColors.line), padding: const EdgeInsets.symmetric(vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  icon: const Icon(Icons.copy_outlined, size: 15),
                  label: Text(AppLang.instance.t('copyCode'), style: const TextStyle(fontSize: 13)),
                  onPressed: () => Clipboard.setData(ClipboardData(text: widget.identity.code)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FipCard(title: AppLang.instance.t('thisDeviceFipBlock'), fip: widget.identity),
          const SizedBox(height: 16),

          // Hesap silme
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: PhotonColors.danger.withOpacity(0.08), border: Border.all(color: PhotonColors.danger.withOpacity(0.27)), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLang.instance.t('deactivateAccountTitle'), style: TextStyle(color: PhotonColors.danger, fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Text(AppLang.instance.t('deactivateAccountBody'), style: PText.meta),
              const SizedBox(height: 16),
              if (!_confirming)
                ElevatedButton(
                  style: photonDangerButtonStyle(),
                  onPressed: () => setState(() => _confirming = true),
                  child: SizedBox(width: double.infinity, child: Text(AppLang.instance.t('deleteAccountButton'), textAlign: TextAlign.center)),
                )
              else
                Row(children: [
                  Expanded(child: OutlinedButton(style: photonGhostButtonStyle(), onPressed: _deleting ? null : () => setState(() => _confirming = false), child: Text(AppLang.instance.t('giveUp')))),
                  const SizedBox(width: 8),
                  Expanded(child: ElevatedButton(
                    style: photonDangerButtonStyle(),
                    onPressed: _deleting ? null : _deactivate,
                    child: _deleting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(AppLang.instance.t('yesDelete')),
                  )),
                ]),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            style: photonGhostButtonStyle(),
            onPressed: () => Navigator.pop(context),
            child: SizedBox(width: double.infinity, child: Text(AppLang.instance.t('back'), textAlign: TextAlign.center)),
          ),
        ],
      ),
    );
  }
}
