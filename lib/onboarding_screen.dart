import 'package:flutter/material.dart';
import 'e2e.dart';
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
  bool _creating = false;

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
    final fip = _preview;
    if (name.isEmpty || fip == null || _creating) return;
    setState(() => _creating = true);
    // Kullanıcının ekranda gördüğü (önizlenen) kimlik kaydedilir; kod farklı çıkmaz.
    await LocalStore.saveIdentity(fip);
    await LocalStore.saveDisplayName(name);
    await ensureE2EKeypair();
    if (!mounted) return;
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
    final ready = _nameCtrl.text.trim().isNotEmpty && !_creating;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
          child: ContentWidth(
            max: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Adım 2 / 2 · Kimlik'),
                const SizedBox(height: Space.s1),
                const Text('Kimliğin bu cihazda doğuyor.', style: KnkText.h1),
                const SizedBox(height: Space.s3),
                const Text(
                  'Aşağıdaki 20 satır yalnızca bu cihazda üretildi ve burada kalır. Arkadaşların seni sadece alttaki 5 haneli kodla bulur.',
                  style: KnkText.bodyDim,
                ),
                const SizedBox(height: Space.s4),
                FipCard(title: 'FIP kimlik bloğu', fip: preview, onRegen: _creating ? null : _regen),
                const SizedBox(height: Space.s4),
                TextField(
                  controller: _nameCtrl,
                  maxLength: 20,
                  decoration: knkInputDecoration('örn. Photon', label: 'Görünen ad (sadece arkadaşların görür)'),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _create(),
                ),
                const SizedBox(height: Space.s1),
                ElevatedButton(
                  onPressed: ready ? _create : null,
                  child: const Text('Kimliği oluştur'),
                ),
              ],
            ),
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
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: KnkColors.panel,
        border: Border.all(color: KnkColors.line),
        borderRadius: BorderRadius.circular(KnkRadius.card),
        boxShadow: knkShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s1, Space.s1),
            child: Row(children: [
              Expanded(child: Text(trUpper(title), overflow: TextOverflow.ellipsis, style: KnkText.label)),
              if (onRegen != null)
                TextButton.icon(
                  onPressed: onRegen,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Yeniden üret', style: TextStyle(fontSize: 13)),
                ),
              if (onRegen == null) const SizedBox(height: Space.s5),
            ]),
          ),
          const Divider(height: 1),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1),
              itemCount: fip.lines.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s1),
                child: Row(children: [
                  SizedBox(
                    width: Space.s4,
                    child: Text((i + 1).toString().padLeft(2, '0'),
                        style: KnkText.meta.merge(KnkText.tabular).copyWith(color: KnkColors.accent2, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text(fip.lines[i], overflow: TextOverflow.ellipsis,
                        style: KnkText.meta.merge(KnkText.tabular).copyWith(fontSize: 13)),
                  ),
                ]),
              ),
            ),
          ),
          Container(
            color: KnkColors.accentWash,
            padding: const EdgeInsets.all(Space.s3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Expanded(child: Text('Bu bloktan türetilen\neşleşme kodu', style: KnkText.small)),
              Text(fip.code, style: KnkText.code.copyWith(fontSize: 34, letterSpacing: 6)),
            ]),
          ),
        ],
      ),
    );
  }
}
