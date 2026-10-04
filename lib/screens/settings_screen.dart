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
  final String displayName;
  /// Hesap silinmeden hemen önce çağrılır (ör. arka plan senkronunu durdurmak için).
  final VoidCallback? onBeforeDeactivate;
  const SettingsScreen({super.key, required this.identity, required this.myServerUrl, this.displayName = '', this.onBeforeDeactivate});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirming = false;
  bool _deleting = false;

  Future<void> _deactivate() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    widget.onBeforeDeactivate?.call();
    final token = await LocalStore.loadOrCreateAuthToken();
    final id = widget.identity;
    // Sunucu yeniden başlamış olabilir: önce kaydı tazele, sonra token ile hesabı sil.
    // Böylece arkadaşların bu hesabın silindiğini görür ve kişiyi listelerinden kaldırır.
    if (!await KnkApi.deactivate(widget.myServerUrl, id.fipId, token)) {
      await KnkApi.registerPresence(widget.myServerUrl, id.fipId, id.code, widget.displayName, authToken: token);
      await KnkApi.deactivate(widget.myServerUrl, id.fipId, token);
    }
    await KnkApi.unregisterOnBridge(id.code, widget.myServerUrl);
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
        padding: const EdgeInsets.fromLTRB(Space.s2, Space.s4, Space.s2, Space.s6),
        children: [
          ContentWidth(
            max: 640,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Kimliğin', style: KnkText.h1),
              const SizedBox(height: Space.s1),
              const Text('Bu bilgiler yalnızca bu cihazda duruyor.', style: KnkText.bodyDim),
              const SizedBox(height: Space.s4),
              FipCard(title: 'Bu cihazın FIP bloğu', fip: widget.identity),
              const SizedBox(height: Space.s5),
              const SectionLabel('Tam adresin'),
              HoverCard(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: myAddress));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adres kopyalandı.'), duration: Duration(seconds: 2)));
                  }
                },
                child: Row(children: [
                  Expanded(child: Text(myAddress, style: KnkText.small.copyWith(color: KnkColors.accent))),
                  const SizedBox(width: Space.s1),
                  const Icon(Icons.content_copy_outlined, size: 18, color: KnkColors.accent),
                ]),
              ),
              const SizedBox(height: Space.s1),
              const Text('Arkadaşların seni eklemek için sadece 5 haneli kodu kullanır; bu adres sorun gidermek için.', style: KnkText.small),
              const SizedBox(height: Space.s6),
              Container(
                padding: const EdgeInsets.all(Space.s3),
                decoration: BoxDecoration(
                  color: KnkColors.danger.withOpacity(0.06),
                  border: Border.all(color: KnkColors.danger.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(KnkRadius.card),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const Text('Hesabı bu cihazdan kaldır', style: TextStyle(fontFamily: KnkFonts.display, fontSize: 19, color: KnkColors.danger)),
                  const SizedBox(height: Space.s1),
                  const Text(
                    'FIP bloğun, kişi listen ve sunucundaki sohbetlerin silinir. Arkadaşlarının listesinden de otomatik olarak kalkarsın. Bu işlem geri alınamaz.',
                    style: KnkText.small,
                  ),
                  const SizedBox(height: Space.s3),
                  if (!_confirming)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        style: knkDangerButtonStyle(),
                        onPressed: () => setState(() => _confirming = true),
                        child: const Text('Hesabı sil'),
                      ),
                    )
                  else
                    Wrap(spacing: Space.s1, runSpacing: Space.s1, children: [
                      ElevatedButton(
                        style: knkDangerButtonStyle(),
                        onPressed: _deleting ? null : _deactivate,
                        child: _deleting
                            ? const SizedBox(width: Space.s2, height: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2A0B08)))
                            : const Text('Evet, kalıcı olarak sil'),
                      ),
                      OutlinedButton(
                        onPressed: _deleting ? null : () => setState(() => _confirming = false),
                        child: const Text('Vazgeç'),
                      ),
                    ]),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
