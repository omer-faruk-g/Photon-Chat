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
      KeyTrust.verified => (KnkColors.accent, Icons.verified_user, 'Doğrulandı',
          '${widget.theirName} ile güvenlik numaranızı karşılaştırdın. Mesajlarınızı yalnızca siz okuyabilirsiniz.'),
      KeyTrust.changed => (KnkColors.danger, Icons.gpp_bad, 'Anahtar değişti!',
          '${widget.theirName} için daha önce doğruladığın anahtar ile şu anki anahtar farklı. Araya biri girmiş olabilir. '
          'Numarayı kişiyle yeniden karşılaştırmadan hassas bir şey paylaşma.'),
      _ => (KnkColors.accent2, Icons.gpp_maybe, 'Doğrulanmadı',
          'Mesajlar şifreli, ama karşındakinin gerçekten ${widget.theirName} olduğundan emin olmak için numarayı karşılaştır.'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(body, style: const TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.5)),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Güvenlik Numarası')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: KnkColors.accent))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _statusCard(),
                const SizedBox(height: 20),
                if (_number == null)
                  const Text('Güvenlik numarası hesaplanamadı (geçersiz anahtar).', style: TextStyle(color: KnkColors.danger))
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                    decoration: BoxDecoration(color: KnkColors.panel, border: Border.all(color: KnkColors.line), borderRadius: BorderRadius.circular(10)),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 18,
                      runSpacing: 12,
                      children: [
                        for (final (i, g) in safetyNumberGroups(_number!).indexed)
                          Text(g, key: ValueKey('safety-group-$i'), style: const TextStyle(
                            color: KnkColors.text, fontSize: 20, fontFamily: 'monospace', letterSpacing: 2, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  '${widget.theirName} ile bu numarayı yüz yüze veya bir telefon görüşmesinde karşılaştırın. '
                  'Onun ekranındaki numara seninkiyle birebir aynıysa "Doğrulandı" olarak işaretle.\n\n'
                  'Numaralar farklıysa mesajlarınızı biri araya girerek okuyabiliyor olabilir.',
                  style: const TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 20),
                if (_trust == KeyTrust.verified)
                  OutlinedButton(
                    style: knkGhostButtonStyle(),
                    onPressed: _busy ? null : () => _setVerified(false),
                    child: const Text('Doğrulamayı kaldır'),
                  )
                else
                  ElevatedButton(
                    style: knkPrimaryButtonStyle(),
                    onPressed: (_busy || _number == null) ? null : () => _setVerified(true),
                    child: Text(_trust == KeyTrust.changed ? 'Numaralar eşleşti, yeni anahtarı doğrula' : 'Numaralar eşleşti, doğrulandı olarak işaretle'),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: knkGhostButtonStyle(),
                  onPressed: _number == null ? null : _copy,
                  icon: const Icon(Icons.copy, size: 15),
                  label: const Text('Numarayı kopyala'),
                ),
              ]),
            ),
    );
  }
}
