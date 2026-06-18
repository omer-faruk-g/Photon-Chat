import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../onboarding_screen.dart';
import '../theme.dart';

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

  @override
  void initState() {
    super.initState();
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
      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: KnkColors.accent, fontSize: 28, fontWeight: FontWeight.bold)),
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
          Center(child: Text(widget.displayName, style: const TextStyle(color: KnkColors.text, fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(height: 20),

          // Durum mesajı
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DURUM MESAJI', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _statusCtrl,
                style: const TextStyle(color: KnkColors.text, fontSize: 13),
                maxLength: 60,
                decoration: InputDecoration(
                  hintText: 'Müsait, Meşgul, Toplantıda…',
                  hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 12),
                  filled: true, fillColor: KnkColors.bg,
                  counterStyle: const TextStyle(color: KnkColors.textDim, fontSize: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: KnkColors.line)),
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

          // Adres
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.accent.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('SENİN ADRESİN', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(myAddress, style: const TextStyle(color: KnkColors.accent, fontSize: 12, fontFamily: 'monospace')),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: KnkColors.text, side: const BorderSide(color: KnkColors.line), padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
              const Text('Hesabı bu cihazdan kaldır', style: TextStyle(color: KnkColors.danger, fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              const Text('FIP bloğun, kişi listen ve aktif sohbetlerin kalıcı olarak silinir.', style: TextStyle(color: KnkColors.textDim, fontSize: 11.5, height: 1.6)),
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
