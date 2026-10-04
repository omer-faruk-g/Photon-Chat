import 'package:flutter/material.dart';
import 'theme.dart';

/// İlk açılış rehberi. Her sayfa tek bir mesaj taşır; sıra gerçek bir akış
/// olduğu için sayfalar numaralıdır.
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
      icon: Icons.sensors,
      title: 'Numaran yok.\nBeş rakamın var.',
      body: 'Photon Chat kimliğini bu cihazda üretir. Telefon numarası, e-posta ya da hesap istemez.',
    ),
    _GuidePage(
      icon: Icons.dns_outlined,
      title: 'Mesajların senin sunucunda bekler.',
      body: 'Merkezi bir sunucu yok. render.com üzerinde ücretsiz bir servis açarsın; bir sonraki adımda adresini soracağız.',
      tip: 'render.com → New → Web Service → bu depo, kök klasör: server',
    ),
    _GuidePage(
      icon: Icons.pin_outlined,
      title: 'Arkadaşın seni kodunla ekler.',
      body: 'Kimliğin oluşunca 5 haneli bir kod alırsın. Arkadaşın sadece bu kodu yazar; sunucunu uygulama arka planda bulur.',
      digits: '08290',
    ),
    _GuidePage(
      icon: Icons.lock_outline,
      title: 'Sunucu mesajı taşır, okuyamaz.',
      body: 'Birebir ve grup mesajları gönderilmeden önce cihazında şifrelenir. Anahtar yalnızca konuşan kişilerde durur.',
    ),
    _GuidePage(
      icon: Icons.verified_user_outlined,
      title: 'Altmış rakam, iki ekran, aynı sıra.',
      body: 'Sohbetteki kalkana dokunup güvenlik numarasını arkadaşınla karşılaştır. Rakamlar aynıysa aranıza kimse girmemiştir.',
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          max: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s1, 0),
                child: Row(children: [
                  const BrandMark(size: 28),
                  const SizedBox(width: Space.s1),
                  const Expanded(child: Text('Photon Chat', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: KnkFonts.display, fontSize: 19, color: KnkColors.text))),
                  Text('${_page + 1} / ${_pages.length}', style: KnkText.small.merge(KnkText.tabular)),
                  const SizedBox(width: Space.s1),
                  TextButton(onPressed: widget.onDone, child: const Text('Atla')),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s3, 0),
                child: Row(
                  children: List.generate(_pages.length, (i) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      margin: EdgeInsets.only(right: i == _pages.length - 1 ? 0 : Space.s1),
                      color: i <= _page ? KnkColors.accent : KnkColors.line,
                    ),
                  )),
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
                padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s3, Space.s4),
                child: ElevatedButton(
                  onPressed: _next,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(last ? 'Başla' : 'Devam'),
                    const SizedBox(width: Space.s1),
                    const Icon(Icons.arrow_forward, size: 18),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidePage {
  final IconData icon;
  final String title;
  final String body;
  final String? tip;
  final String? digits;
  const _GuidePage({required this.icon, required this.title, required this.body, this.tip, this.digits});
}

class _PageContent extends StatelessWidget {
  final _GuidePage page;
  const _PageContent({required this.page});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Space.s6, height: Space.s6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KnkColors.accentWash,
              borderRadius: BorderRadius.circular(KnkRadius.card),
              border: Border.all(color: KnkColors.line),
            ),
            child: Icon(page.icon, color: KnkColors.accent, size: 28),
          ),
          const SizedBox(height: Space.s4),
          Text(page.title, style: KnkText.h1),
          const SizedBox(height: Space.s3),
          Text(page.body, style: KnkText.bodyDim),
          if (page.digits != null) ...[
            const SizedBox(height: Space.s4),
            LayoutBuilder(builder: (context, c) {
              // 5 kutu + 4 boşluk; dar ekranda kutular küçülür, geniş ekranda 48'de kalır.
              final box = ((c.maxWidth - Space.s1 * 4) / 5).clamp(0.0, Space.s5);
              return Row(children: [
                for (final (i, d) in page.digits!.split('').indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s1),
                  // Köşe yarıçapı tek renkli kenarlık ister; yeşil alt çizgi ayrı bir şerit olarak çizilir.
                  Container(
                    width: box, height: box * 4 / 3,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: KnkColors.panel,
                      borderRadius: BorderRadius.circular(KnkRadius.card),
                      border: Border.all(color: KnkColors.line),
                    ),
                    child: Stack(children: [
                      Center(child: Text(d, style: KnkText.h2.merge(KnkText.tabular).copyWith(fontFamily: KnkFonts.body, fontWeight: FontWeight.w600))),
                      const Positioned(left: 0, right: 0, bottom: 0, child: SizedBox(height: 3, child: ColoredBox(color: KnkColors.accent))),
                    ]),
                  ),
                ],
              ]);
            }),
            const SizedBox(height: Space.s1),
            const Text('örnek kod', style: KnkText.meta),
          ],
          if (page.tip != null) ...[
            const SizedBox(height: Space.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.s2),
              decoration: BoxDecoration(
                color: KnkColors.panel,
                border: Border.all(color: KnkColors.line),
                borderRadius: BorderRadius.circular(KnkRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: KnkColors.accent2, size: 18),
                  const SizedBox(width: Space.s1),
                  Expanded(child: Text(page.tip!, style: KnkText.small)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
