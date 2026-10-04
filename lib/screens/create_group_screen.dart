import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';
import '../e2e.dart';

class CreateGroupScreen extends StatefulWidget {
  final FipBlock identity;
  final String displayName;
  final String myServerUrl;
  const CreateGroupScreen({super.key, required this.identity, required this.displayName, required this.myServerUrl});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  Group? _created;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_loading) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Grup adı boş olamaz'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final myPub = await getMyPublicKeyBase64();
      final data = await KnkApi.createGroup(
        widget.myServerUrl,
        ownerFipId: widget.identity.fipId,
        ownerName: widget.displayName,
        name: name,
        ownerServerUrl: widget.myServerUrl,
        ownerPublicKey: myPub,
      );
      if (!mounted) return;
      if (data == null) { setState(() { _error = 'Grup oluşturulamadı. Sunucu bağlantını kontrol et.'; _loading = false; }); return; }
      if (data['token'] == null) { setState(() { _error = 'Sunucun eski bir sürüm. Grup için sunucunu güncelle.'; _loading = false; }); return; }
      final (keyId, key) = generateGroupKeyEntry();
      final group = Group(
        groupId: data['groupId'] as String,
        groupCode: data['groupCode'] as String,
        name: name,
        ownerFipId: widget.identity.fipId,
        ownerServerUrl: widget.myServerUrl,
        isOwner: true,
        token: data['token'] as String?,
        ownerPublicKey: myPub,
        // İlk uçtan uca grup anahtarı: yalnızca bu cihazda üretilir ve saklanır.
        keyring: {keyId: key},
        currentKeyId: keyId,
        members: [GroupMember(fipId: widget.identity.fipId, name: widget.displayName, serverUrl: widget.myServerUrl, publicKey: myPub)],
      );
      setState(() { _created = group; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Grup oluşturulamadı.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Grup oluşturulduktan sonra geri tuşuyla çıkılsa bile grup listeye eklenir.
    return PopScope(
      canPop: _created == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _created != null) Navigator.pop(context, _created);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Grup oluştur')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
          child: ContentWidth(max: 560, child: _created == null ? _buildForm() : _buildSuccess()),
        ),
      ),
    );
  }

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Gruba bir ad ver.', style: KnkText.h1),
      const SizedBox(height: Space.s3),
      const Text('Grup senin sunucunda yaşar ve şifreleme anahtarı bu cihazda üretilir. Kimin katılacağına sen karar verirsin.', style: KnkText.bodyDim),
      const SizedBox(height: Space.s4),
      TextField(
        controller: _nameCtrl,
        maxLength: 40,
        onSubmitted: (_) => _create(),
        decoration: knkInputDecoration('örn. Hafta sonu ekibi', label: 'Grup adı', error: _error),
      ),
      const SizedBox(height: Space.s1),
      ElevatedButton(
        onPressed: _loading ? null : _create,
        child: _loading
            ? const SizedBox(height: Space.s2, width: Space.s2, child: CircularProgressIndicator(strokeWidth: 2, color: KnkColors.onAccent))
            : const Text('Grubu oluştur'),
      ),
    ],
  );

  Widget _buildSuccess() {
    final g = _created!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle_outline, color: KnkColors.accent, size: 32),
        const SizedBox(height: Space.s2),
        Text('${g.name} hazır.', style: KnkText.h1),
        const SizedBox(height: Space.s3),
        const Text('Bu adresi katılmasını istediğin kişilere gönder. Katılma istekleri grubun içinde, sağ üstte görünür.', style: KnkText.bodyDim),
        const SizedBox(height: Space.s4),
        Container(
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(color: KnkColors.accentWash, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GRUP ADRESİ', style: KnkText.label),
            const SizedBox(height: Space.s1),
            Text(g.groupCode, style: KnkText.code.copyWith(fontSize: 34, letterSpacing: 6)),
            const SizedBox(height: Space.s1),
            SelectableText('@${g.ownerServerUrl}', style: KnkText.small),
          ]),
        ),
        const SizedBox(height: Space.s2),
        OutlinedButton.icon(
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: const Text('Adresi kopyala'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: g.address));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Grup adresi kopyalandı.'), duration: Duration(seconds: 2)));
          },
        ),
        const SizedBox(height: Space.s1),
        ElevatedButton(onPressed: () => Navigator.pop(context, g), child: const Text('Bitti')),
      ],
    );
  }
}
