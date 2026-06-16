import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'theme.dart';

class ServerSetupScreen extends StatefulWidget {
  final void Function(String url) onDone;
  const ServerSetupScreen({super.key, required this.onDone});
  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _test() async {
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) { setState(() => _error = 'URL boş olamaz'); return; }
    final url = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.get(Uri.parse('$url/lookup/00000')).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200 || r.statusCode == 404) {
        widget.onDone(url);
      } else {
        setState(() => _error = 'Sunucu yanıt vermedi (${r.statusCode})');
      }
    } catch (e) {
      setState(() => _error = 'Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KnkColors.bg,
      body: SafeArea(
        child: Padding(
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
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
                  errorText: _error,
                  errorStyle: const TextStyle(color: KnkColors.danger),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
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
