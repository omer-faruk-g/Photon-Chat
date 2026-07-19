import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'theme.dart';
import 'device_manager.dart';

class ServerSetupScreen extends StatefulWidget {
  final void Function(String url) onDone;
  final void Function(String url, String ownerFipId)? onDeviceLink;
  const ServerSetupScreen({super.key, required this.onDone, this.onDeviceLink});
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
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      setState(() => _error = "URL 'https://' ile başlamalı");
      return;
    }
    final url = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.host.isEmpty) {
      setState(() => _error = 'Geçersiz URL biçimi');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final r = await http.get(Uri.parse('$url/lookup/00000')).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (r.statusCode == 200 || r.statusCode == 404) {
        final banned = await DeviceManager.isServerBanned(url, '');
        if (!mounted) return;
        if (banned) {
          setState(() => _error = 'Bu sunucuya erişiminiz kalıcı olarak yasaklanmış.');
          return;
        }

        final presenceCheck = await _checkExistingPresence(url);
        if (!mounted) return;
        if (presenceCheck != null && widget.onDeviceLink != null) {
          widget.onDeviceLink!(url, presenceCheck);
        } else {
          widget.onDone(url);
        }
      } else {
        setState(() => _error = 'Sunucu yanıt vermedi (${r.statusCode})');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<String?> _checkExistingPresence(String url) async {
    try {
      final r = await http.get(Uri.parse('$url/presence/owner')).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map<String, dynamic>;
        final ownerFipId = data['fipId'] as String?;
        if (ownerFipId != null && ownerFipId.isNotEmpty) return ownerFipId;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text('Sunucu Kurulumu', style: TextStyle(color: PhotonColors.text, fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(
                'Photon Chat kendi sunucunu kullanır.\n\nrender.com üzerinde ücretsiz bir Node.js servisi aç ve adresini buraya gir.',
                style: TextStyle(color: PhotonColors.textDim, fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: PhotonColors.panelAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: PhotonColors.line)),
                child: Text(
                  '1. render.com → New → Web Service\n2. GitHub reposunu seç (server/ klasörü)\n3. Free plan → Deploy\n4. Verilen URL\'yi buraya yapıştır',
                  style: TextStyle(color: PhotonColors.textDim, fontSize: 12, height: 1.8, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _ctrl,
                style: TextStyle(color: PhotonColors.text),
                decoration: InputDecoration(
                  labelText: 'Render URL',
                  hintText: 'https://photon-chat-xxxx.onrender.com',
                  hintStyle: TextStyle(color: PhotonColors.textDim, fontSize: 13),
                  labelStyle: TextStyle(color: PhotonColors.textDim),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.line), borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: PhotonColors.accent), borderRadius: BorderRadius.circular(8)),
                  errorText: _error,
                  errorStyle: TextStyle(color: PhotonColors.danger),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: photonPrimaryButtonStyle(),
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
