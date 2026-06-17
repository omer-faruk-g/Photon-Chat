import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../knk_api.dart';
import '../local_store.dart';
import '../onboarding_screen.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final FipBlock identity;
  final String myServerUrl;
  const SettingsScreen({super.key, required this.identity, required this.myServerUrl});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirming = false;
  bool _deleting = false;

  Future<void> _deactivate() async {
    setState(() => _deleting = true);
    await KnkApi.deactivate(widget.myServerUrl, widget.identity.fipId);
    await LocalStore.wipeIdentity();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final myAddress = '${widget.identity.code}@${widget.myServerUrl}';
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  label: const Text('Adresi Kopyala', style: TextStyle(fontSize: 13)),
                  onPressed: () => Clipboard.setData(ClipboardData(text: myAddress)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FipCard(title: 'BU CİHAZIN FIP BLOĞU', fip: widget.identity),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1A1314), border: Border.all(color: KnkColors.danger.withOpacity(0.27)), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(style: knkGhostButtonStyle(), onPressed: _deleting ? null : () => setState(() => _confirming = false), child: const Text('Vazgeç'))),
                      const SizedBox(width: 10),
                      Expanded(child: ElevatedButton(
                        style: knkDangerButtonStyle(),
                        onPressed: _deleting ? null : _deactivate,
                        child: _deleting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Evet, kalıcı olarak sil'),
                      )),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(style: knkGhostButtonStyle(), onPressed: () => Navigator.pop(context), child: const SizedBox(width: double.infinity, child: Text('Geri', textAlign: TextAlign.center))),
        ],
      ),
    );
  }
}
