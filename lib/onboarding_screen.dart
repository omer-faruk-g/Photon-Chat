import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fip.dart';
import 'local_store.dart';
import 'theme.dart';

/// İlk açılışta cihazda yeni bir FIP kimliği oluşturma ekranı.
class OnboardingScreen extends StatefulWidget {
  final String myServerUrl;
  final void Function(FipBlock fip, String name) onCreated;
  const OnboardingScreen({super.key, required this.myServerUrl, required this.onCreated});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  FipBlock? _preview;
  final _nameCtrl = TextEditingController();
  FipBlock? _created;

  @override
  void initState() {
    super.initState();
    _preview = FipBlock.generate();
  }

  void _regen() {
    setState(() => _preview = FipBlock.generate());
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _preview == null) return;
    final fip = await LocalStore.createIdentity();
    await LocalStore.saveDisplayName(name);
    setState(() => _created = fip);
    widget.onCreated(fip, name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview!;
    return Scaffold(
      backgroundColor: KnkColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'PHOTON CHAT',
                      style: TextStyle(
                        fontFamily: 'sans-serif',
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                        letterSpacing: 4,
                        color: KnkColors.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'FIP tabanlı kimlik · sunucusuz rehber · numarasız',
                      style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FipCard(
                title: 'FIP — ÖNİZLEME',
                fip: preview,
                onRegen: _regen,
              ),
              const SizedBox(height: 24),
              const Text('Görünen ad (sadece arkadaşların görür)',
                  style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                maxLength: 20,
                style: TextStyle(color: KnkColors.text, fontSize: 15),
                decoration: knkInputDecoration('örn. Photon'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                style: knkPrimaryButtonStyle(),
                onPressed: _nameCtrl.text.trim().isEmpty ? null : _create,
                child: const Text('Kimliği bu cihazda oluştur'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Bu işlem internet hesabı, telefon numarası ya da e-posta gerektirmez. '
                'FIP bloğun ve eşleşme kodun bu cihazda saklanır.',
                style: TextStyle(color: KnkColors.textDim, fontSize: 11, height: 1.6),
              ),
              if (_created != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KnkColors.panel,
                    border: Border.all(color: KnkColors.accent.withOpacity(0.4)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('SENİN ADRESİN', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Text(
                      '${_created!.code}@${widget.myServerUrl}',
                      style: TextStyle(color: KnkColors.accent, fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: KnkColors.text,
                          side: BorderSide(color: KnkColors.line),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Adresi Kopyala', style: TextStyle(fontSize: 13)),
                        onPressed: () => Clipboard.setData(ClipboardData(text: '${_created!.code}@${widget.myServerUrl}')),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// FIP bloğunu 20 satır halinde gösteren kart (önizleme ve ayarlarda kullanılır).
class FipCard extends StatelessWidget {
  final String title;
  final FipBlock fip;
  final VoidCallback? onRegen;

  const FipCard({super.key, required this.title, required this.fip, this.onRegen});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KnkColors.panel,
        border: Border.all(color: KnkColors.line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
              if (onRegen != null)
                GestureDetector(
                  onTap: onRegen,
                  child: const Text('yeniden üret',
                      style: TextStyle(
                          color: KnkColors.accent2,
                          fontSize: 11,
                          decoration: TextDecoration.underline)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: KnkColors.bg,
              border: Border.all(color: KnkColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: fip.lines.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text((i + 1).toString().padLeft(2, '0'),
                            style: const TextStyle(
                                color: KnkColors.accent2, fontSize: 11, fontFamily: 'monospace')),
                      ),
                      Expanded(
                        child: Text(
                          fip.lines[i],
                          style: const TextStyle(
                              color: Color(0xFF9FE8CC),
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              letterSpacing: 0.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('EŞLEŞME KODU',
                  style: TextStyle(color: KnkColors.textDim, fontSize: 11, letterSpacing: 1.5)),
              Text(
                fip.code,
                style: const TextStyle(
                  color: KnkColors.accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
