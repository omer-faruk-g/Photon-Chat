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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
          child: ContentWidth(
            max: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Adım 1 / 2 · Sunucu'),
                const SizedBox(height: Space.s1),
                const Text('Mesajların nerede beklesin?', style: KnkText.h1),
                const SizedBox(height: Space.s3),
                const Text(
                  'Photon Chat merkezi bir sunucu kullanmaz. render.com üzerinde ücretsiz açtığın servisin adresini gir.',
                  style: KnkText.bodyDim,
                ),
                const SizedBox(height: Space.s4),
                TextField(
                  controller: _ctrl,
                  decoration: knkInputDecoration('https://photon-chat-xxxx.onrender.com', label: 'Sunucu adresi', error: _error),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) { if (_error != null) setState(() => _error = null); },
                  onSubmitted: (_) { if (!_loading) _test(); },
                ),
                const SizedBox(height: Space.s2),
                ElevatedButton(
                  onPressed: _loading ? null : _test,
                  child: _loading
                      ? const SizedBox(height: Space.s2, width: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.onAccent))
                      : const Text('Bağlan'),
                ),
                const SizedBox(height: Space.s5),
                const SectionLabel('Sunucun yok mu?'),
                const SizedBox(height: Space.s1),
                for (final (i, step) in const [
                  ('render.com’da servis aç', 'Ücretsiz hesapla New → Web Service, bu depoyu seç, kök klasör: server.'),
                  ('Adresi kopyala', 'Birkaç dakika sonra https://…onrender.com adresin hazır olur.'),
                  ('Buraya yapıştır', 'Ücretsiz sunucu uykudaysa ilk bağlantı bir dakika kadar sürebilir.'),
                ].indexed) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: Space.s4, child: Text('${i + 1}', style: KnkText.h3.copyWith(color: KnkColors.accent2))),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(step.$1, style: KnkText.strong),
                      const SizedBox(height: Space.s1),
                      Text(step.$2, style: KnkText.small),
                    ])),
                  ]),
                  const SizedBox(height: Space.s2),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
