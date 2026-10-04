import 'dart:async';
import 'package:flutter/material.dart';
import 'knk_api.dart';
import 'theme.dart';

/// Kullanıcının girdiği adresi normalize eder: boşlukları ve sondaki '/' işaretlerini
/// atar, şema yoksa https ekler. Geçersizse null döner.
String? normalizeServerUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return null;
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http') || uri.host.isEmpty) return null;
  return url;
}

class ServerSetupScreen extends StatefulWidget {
  final Future<void> Function(String url) onDone;
  const ServerSetupScreen({super.key, required this.onDone});
  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (_ctrl.text.trim().isEmpty) { setState(() => _error = 'URL boş olamaz'); return; }
    final url = normalizeServerUrl(_ctrl.text);
    if (url == null) { setState(() => _error = 'Geçerli bir adres gir (https://...)'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      var ok = false;
      var finalUrl = url;
      try {
        ok = await KnkApi.isPhotonServer(url);
      } on TimeoutException {
        rethrow;
      } catch (_) {
        // Şema yazılmadıysa (ör. "192.168.1.5:3000") HTTPS başarısız olunca HTTP'yi dene.
        if (_ctrl.text.contains('://')) rethrow;
        finalUrl = url.replaceFirst('https://', 'http://');
        ok = await KnkApi.isPhotonServer(finalUrl);
      }
      if (ok) {
        await widget.onDone(finalUrl);
        return;
      }
      if (mounted) setState(() => _error = 'Bu adres bir Photon Chat sunucusu değil.');
    } on TimeoutException {
      if (mounted) setState(() => _error = 'Sunucu yanıt vermedi. Ücretsiz sunucular uykudan uyanırken 1 dakika sürebilir, tekrar dene.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Sunucuya bağlanılamadı. Adresi ve internet bağlantını kontrol et.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KnkColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text('Sunucu Kurulumu', style: TextStyle(color: KnkColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text(
                'Photon Chat kendi sunucunu kullanır.\n\nrender.com üzerinde ücretsiz bir Node.js servisi aç ve adresini buraya gir.',
                style: TextStyle(color: KnkColors.textDim, fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: KnkColors.panelAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: KnkColors.line)),
                child: const Text(
                  '1. render.com → New → Web Service\n2. GitHub reposunu seç (server/ klasörü)\n3. Free plan → Deploy\n4. Verilen URL\'yi buraya yapıştır',
                  style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.8, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                style: const TextStyle(color: KnkColors.text),
                decoration: InputDecoration(
                  labelText: 'Render URL',
                  hintText: 'https://photon-chat-xxxx.onrender.com',
                  hintStyle: const TextStyle(color: KnkColors.textDim, fontSize: 13),
                  labelStyle: const TextStyle(color: KnkColors.textDim),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
                  errorText: _error,
                  errorStyle: const TextStyle(color: KnkColors.danger),
                  errorMaxLines: 3,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) { if (!_loading) _test(); },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: knkPrimaryButtonStyle(),
                  onPressed: _loading ? null : _test,
                  child: _loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Bağlan ve Devam Et'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
