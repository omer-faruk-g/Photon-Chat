import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../e2e.dart';
import '../local_store.dart';
import '../theme.dart';

String? _computeSafetyNumber(List<String> a) =>
    safetyNumber(myFipId: a[0], myPublicKey: a[1], theirFipId: a[2], theirPublicKey: a[3]);

/// Güvenlik numarası ekranı: iki kişi bu numarayı yüz yüze veya telefonda
/// karşılaştırır; eşleşiyorsa araya kimse girmemiştir ve anahtar doğrulanır.
class VerifyKeyScreen extends StatefulWidget {
  final String myFipId;
  final String theirFipId;
  final String theirName;
  final String theirPublicKey;

  const VerifyKeyScreen({super.key, required this.myFipId, required this.theirFipId, required this.theirName, required this.theirPublicKey});

  @override
  State<VerifyKeyScreen> createState() => _VerifyKeyScreenState();
}

class _VerifyKeyScreenState extends State<VerifyKeyScreen> {
  String? _number;
  KeyTrust _trust = KeyTrust.unverified;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myPub = await getMyPublicKeyBase64();
    final verified = await LocalStore.loadVerifiedKeys();
    // 2 x 5200 tur SHA-512: arayüzü takılttırmamak için ayrı isolate'te hesapla.
    final number = await compute(_computeSafetyNumber, [widget.myFipId, myPub, widget.theirFipId, widget.theirPublicKey]);
    if (!mounted) return;
    setState(() {
      _number = number;
      _trust = keyTrust(verified, widget.theirFipId, widget.theirPublicKey);
      _loading = false;
    });
  }

  Future<void> _setVerified(bool verified) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (verified) {
      await LocalStore.setVerifiedKey(widget.theirFipId, widget.theirPublicKey);
    } else {
      await LocalStore.removeVerifiedKey(widget.theirFipId);
    }
    if (!mounted) return;
    setState(() { _trust = verified ? KeyTrust.verified : KeyTrust.unverified; _busy = false; });
  }

  Future<void> _copy() async {
    final n = _number;
    if (n == null) return;
    await Clipboard.setData(ClipboardData(text: safetyNumberGroups(n).join(' ')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Güvenlik numarası kopyalandı.'), duration: Duration(seconds: 2)));
    }
  }

  Widget _statusCard() {
    final (Color color, IconData icon, String title, String body) = switch (_trust) {
      KeyTrust.verified => (KnkColors.accent, Icons.verified_user_outlined, 'Doğrulandı',
          '${widget.theirName} ile güvenlik numaranızı karşılaştırdın. Mesajlarınızı yalnızca siz okuyabilirsiniz.'),
      KeyTrust.changed => (KnkColors.danger, Icons.gpp_bad_outlined, 'Anahtar değişti',
          '${widget.theirName} için daha önce doğruladığın anahtar ile şu anki anahtar farklı. Araya biri girmiş olabilir. '
          'Numarayı kişiyle yeniden karşılaştırmadan hassas bir şey paylaşma.'),
      _ => (KnkColors.accent2, Icons.gpp_maybe_outlined, 'Doğrulanmadı',
          'Mesajlar şifreli. Karşındakinin gerçekten ${widget.theirName} olduğundan emin olmak için numarayı karşılaştır.'),
    };
    return Container(
      padding: const EdgeInsets.all(Space.s2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(KnkRadius.card),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: Space.s2),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: Space.s1),
          Text(body, style: KnkText.small),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Güvenlik numarası')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s5),
              child: ContentWidth(
                max: 560,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${widget.theirName} ile karşılaştır.', style: KnkText.h1),
                  const SizedBox(height: Space.s3),
                  const Text(
                    'Yüz yüze ya da telefonda, onun ekranındaki numarayı seninkiyle oku. Altmış rakamın hepsi aynı sıradaysa aranıza kimse girmemiştir.',
                    style: KnkText.bodyDim,
                  ),
                  const SizedBox(height: Space.s4),
                  if (_number == null)
                    const NoticeBar(icon: Icons.error_outline, text: 'Güvenlik numarası hesaplanamadı (geçersiz anahtar).', tone: KnkColors.danger)
                  else
                    Container(
                      padding: const EdgeInsets.all(Space.s3),
                      decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(KnkRadius.card), boxShadow: knkShadow()),
                      child: LayoutBuilder(builder: (context, c) {
                        final groups = safetyNumberGroups(_number!);
                        final cols = c.maxWidth < 300 ? 3 : 4;
                        return Wrap(
                          spacing: Space.s3,
                          runSpacing: Space.s2,
                          children: [
                            for (final (i, g) in groups.indexed)
                              SizedBox(
                                width: (c.maxWidth - Space.s3 * (cols - 1)) / cols,
                                child: Text(g, key: ValueKey('safety-group-$i'),
                                    style: KnkText.tabular.copyWith(fontFamily: KnkFonts.body, color: KnkColors.text, fontSize: 19, letterSpacing: 2, fontWeight: FontWeight.w500)),
                              ),
                          ],
                        );
                      }),
                    ),
                  const SizedBox(height: Space.s3),
                  _statusCard(),
                  const SizedBox(height: Space.s3),
                  if (_trust == KeyTrust.verified)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _setVerified(false),
                      child: const Text('Doğrulamayı kaldır'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: (_busy || _number == null) ? null : () => _setVerified(true),
                      icon: const Icon(Icons.verified_user_outlined, size: 18),
                      label: Text(_trust == KeyTrust.changed ? 'Numaralar eşleşti, yeni anahtarı doğrula' : 'Numaralar eşleşti, doğrulandı olarak işaretle'),
                    ),
                  const SizedBox(height: Space.s1),
                  OutlinedButton.icon(
                    onPressed: _number == null ? null : _copy,
                    icon: const Icon(Icons.content_copy_outlined, size: 18),
                    label: const Text('Numarayı kopyala'),
                  ),
                ]),
              ),
            ),
    );
  }
}
