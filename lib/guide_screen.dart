import 'package:flutter/material.dart';
import 'theme.dart';

class GuideScreen extends StatefulWidget {
  final VoidCallback onDone;
  const GuideScreen({super.key, required this.onDone});
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _GuidePage(
      icon: '⚡',
      title: "Photon Chat'e Hoş Geldin",
      body: 'Telefon numarası yok. E-posta yok. Hesap yok.\n\nSadece bir kriptografik kimlik — cihazında oluşturulur, kimseyle paylaşılmaz.',
    ),
    _GuidePage(
      icon: '🌐',
      title: 'Kendi Sunucunu Kur (Bir Kez)',
      body: 'Photon Chat merkezi bir sunucu kullanmaz.\n\nrender.com üzerinde ücretsiz kendi sunucunu çalıştır. Bu kurulumu yalnızca bir kez yapman yeterli — sonraki açılışlarda tekrar sorulmaz.',
      tip: 'render.com → New Web Service → ücretsiz plan',
    ),
    _GuidePage(
      icon: '🔢',
      title: 'Senin Kodun',
      body: 'Kimliğin oluşturulunca sana 5 haneli bir eşleşme kodu verilir.\n\nBu kod senin tek adresindir. Arkadaşlarına sadece bu kodu ver — başka bir şey gerekmez.',
      highlight: '1 2 3 4 5',
    ),
    _GuidePage(
      icon: '🤝',
      title: 'Arkadaş Ekle',
      body: 'Arkadaşının 5 haneli kodunu gir — ya da QR kodunu tara.\n\nİstek bridge üzerinden iletilir. Kabul ederse ikiniz bağlanırsınız.\n\nSunucu URL\'si paylaşmanıza gerek yok.',
    ),
    _GuidePage(
      icon: '👥',
      title: 'Grup Sohbetleri',
      body: 'Gruplar merkeziyetsizdir — her üyenin sunucusu grubun bir parçasını taşır.\n\n• Grup oluştur → sana 7 haneli bir kod verilir\n• Bu kodu paylaş → üyeler katılmak için gönderir\n• Sen kabul et → mesajlaşma başlar',
    ),
    _GuidePage(
      icon: '🔒',
      title: 'Gizlilik',
      body: "Sunucu hiçbir veriyi kalıcı olarak saklamaz — her şey RAM'dedir.\n\n• Uygulama kapatılırken sohbetleri imha edebilirsin\n• Hesabı sil → tüm veriler anında yok edilir\n• Kişi listesi yalnızca cihazında tutulur\n• Sunucu sadece şifreli blob'ları iletir",
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    } else {
      widget.onDone();
    }
  }

  void _skip() => widget.onDone();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KnkColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: List.generate(_pages.length, (i) => Expanded(
                  child: Container(
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: i <= _page ? KnkColors.accent : KnkColors.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _skip,
                child: Text('Atla', style: TextStyle(color: KnkColors.textDim, fontSize: 13)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageContent(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: knkPrimaryButtonStyle(),
                  onPressed: _next,
                  child: Text(
                    _page == _pages.length - 1 ? 'Hadi Başlayalım →' : 'Devam →',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage {
  final String icon;
  final String title;
  final String body;
  final String? tip;
  final String? highlight;
  const _GuidePage({required this.icon, required this.title, required this.body, this.tip, this.highlight});
}

class _PageContent extends StatelessWidget {
  final _GuidePage page;
  const _PageContent({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Container(
            width: 72, height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KnkColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: KnkColors.accent.withOpacity(0.25)),
            ),
            child: Text(page.icon, style: const TextStyle(fontSize: 34)),
          ),
          const SizedBox(height: 24),
          Text(page.title, style: TextStyle(color: KnkColors.text, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
          const SizedBox(height: 18),
          Text(page.body, style: TextStyle(color: KnkColors.textDim, fontSize: 14, height: 1.8)),
          if (page.highlight != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: KnkColors.accent.withOpacity(0.08),
                border: Border.all(color: KnkColors.accent.withOpacity(0.35)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                page.highlight!,
                textAlign: TextAlign.center,
                style: TextStyle(color: KnkColors.accent, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: 'monospace'),
              ),
            ),
          ],
          if (page.tip != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: KnkColors.panelAlt,
                border: Border.all(color: KnkColors.line),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      page.tip!,
                      style: TextStyle(color: KnkColors.textDim, fontSize: 12, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
