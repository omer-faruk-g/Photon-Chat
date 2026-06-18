import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../fip.dart';
import '../local_store.dart';
import '../knk_api.dart';
import '../theme.dart';

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

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Grup adı boş olamaz'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await KnkApi.createGroup(
        widget.myServerUrl,
        ownerFipId: widget.identity.fipId,
        ownerName: widget.displayName,
        name: name,
        ownerServerUrl: widget.myServerUrl,
      );
      if (data == null) { setState(() { _error = 'Grup oluşturulamadı'; _loading = false; }); return; }
      final group = Group(
        groupId: data['groupId'] as String,
        groupCode: data['groupCode'] as String,
        name: name,
        ownerFipId: widget.identity.fipId,
        ownerServerUrl: widget.myServerUrl,
        isOwner: true,
        members: [],
      );
      setState(() { _created = group; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Hata: $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Grup Oluştur')),
      backgroundColor: KnkColors.bg,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _created == null ? _buildForm() : _buildSuccess(),
      ),
    );
  }

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Grup adı gir. Oluşturulduktan sonra paylaşabilecegin 7 haneli bir kod alacaksın.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
      const SizedBox(height: 24),
      TextField(
        controller: _nameCtrl,
        style: TextStyle(color: KnkColors.text),
        decoration: InputDecoration(
          labelText: 'Grup Adı',
          labelStyle: TextStyle(color: KnkColors.textDim),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.line), borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KnkColors.accent), borderRadius: BorderRadius.circular(8)),
          errorText: _error,
          errorStyle: TextStyle(color: KnkColors.danger),
        ),
      ),
      const SizedBox(height: 20),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: knkPrimaryButtonStyle(),
          onPressed: _loading ? null : _create,
          child: _loading
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Oluştur'),
        ),
      ),
    ],
  );

  Widget _buildSuccess() {
    final g = _created!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Grup oluşturuldu! Aşağıdaki adresi arkadaşlarınla paylaş.', style: TextStyle(color: KnkColors.textDim, fontSize: 13, height: 1.6)),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.accent.withOpacity(0.4)), borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('GRUP ADRESİ', style: TextStyle(color: KnkColors.textDim, fontSize: 10, letterSpacing: 1.5)),
            const SizedBox(height: 8),
            Text(g.address, style: TextStyle(color: KnkColors.accent, fontSize: 13, fontFamily: 'monospace')),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: KnkColors.text, side: BorderSide(color: KnkColors.line), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Adresi Kopyala'),
            onPressed: () => Clipboard.setData(ClipboardData(text: g.address)),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: knkPrimaryButtonStyle(),
            onPressed: () => Navigator.pop(context, g),
            child: const Text('Tamam'),
          ),
        ),
      ],
    );
  }
}
