import 'package:flutter/material.dart';
import 'i18n.dart';
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

  List<_GuidePage> get _pages => [
    _GuidePage(
      icon: Icons.sensors_outlined,
      title: AppLang.instance.t('guideWelcomeTitle'),
      body: AppLang.instance.t('guideWelcomeBody'),
    ),
    _GuidePage(
      icon: Icons.dns_outlined,
      title: AppLang.instance.t('guideSetupServer'),
      body: AppLang.instance.t('guideServerBody'),
      tip: AppLang.instance.t('guideServerTip'),
    ),
    _GuidePage(
      icon: Icons.pin_outlined,
      title: AppLang.instance.t('guideYourCode'),
      body: AppLang.instance.t('guideCodeBody'),
      highlight: '12345',
    ),
    _GuidePage(
      icon: Icons.person_add_outlined,
      title: AppLang.instance.t('guideAddFriend'),
      body: AppLang.instance.t('guideAddFriendBody'),
    ),
    _GuidePage(
      icon: Icons.group_outlined,
      title: AppLang.instance.t('guideGroupChats'),
      body: AppLang.instance.t('guideGroupBody'),
    ),
    _GuidePage(
      icon: Icons.lock_outline,
      title: AppLang.instance.t('guidePrivacy'),
      body: AppLang.instance.t('guidePrivacyBody'),
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PhotonColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s3, Space.s2, Space.s1, 0),
              child: Row(children: [
                BrandMark(size: 28),
                const SizedBox(width: Space.s1),
                Expanded(child: Text('Photon Chat', maxLines: 1, overflow: TextOverflow.ellipsis, style: PText.h2)),
                Text('${_page + 1} / ${_pages.length}', style: PText.small.merge(PText.tabular)),
                const SizedBox(width: Space.s1),
                // Son sayfada da yer tutsun ki başlık zıplamasın.
                Opacity(
                  opacity: _page == _pages.length - 1 ? 0 : 1,
                  child: TextButton(
                    onPressed: _page == _pages.length - 1 ? null : _skip,
                    child: Text(AppLang.instance.t('skip')),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s3, Space.s1, Space.s3, 0),
              child: Row(
                children: List.generate(_pages.length, (i) => Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 3,
                    margin: EdgeInsets.only(right: i == _pages.length - 1 ? 0 : Space.s1),
                    color: i <= _page ? PhotonColors.accent : PhotonColors.line,
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
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  child: Text(_page == _pages.length - 1 ? AppLang.instance.t('letsStart') : AppLang.instance.t('continueArrow')),
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
  final IconData icon;
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
      padding: const EdgeInsets.fromLTRB(Space.s3, Space.s5, Space.s3, Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: Space.s6, height: Space.s6,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PhotonColors.accentWash,
              borderRadius: BorderRadius.circular(PhotonRadius.card),
              border: Border.all(color: PhotonColors.line),
            ),
            child: Icon(page.icon, color: PhotonColors.accent, size: 28),
          ),
          const SizedBox(height: Space.s4),
          Text(page.title, style: PText.display.copyWith(fontSize: 30)),
          const SizedBox(height: Space.s3),
          Text(page.body, style: PText.bodyDim),
          if (page.highlight != null) ...[
            const SizedBox(height: Space.s4),
            LayoutBuilder(builder: (context, c) {
              // 5 kutu + 4 boşluk; dar ekranda kutular küçülür, geniş ekranda 48'de kalır.
              final box = ((c.maxWidth - Space.s1 * 4) / 5).clamp(0.0, Space.s5);
              return Row(children: [
                for (final (i, d) in page.highlight!.split('').indexed) ...[
                  if (i > 0) const SizedBox(width: Space.s1),
                  Container(
                    width: box, height: box * 4 / 3,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: PhotonColors.panel,
                      borderRadius: BorderRadius.circular(PhotonRadius.card),
                      border: Border.all(color: PhotonColors.line),
                    ),
                    child: Stack(children: [
                      Center(child: Text(d, style: PText.h2.merge(PText.tabular).copyWith(fontFamily: PhotonFonts.body, fontWeight: FontWeight.w600))),
                      Positioned(left: 0, right: 0, bottom: 0, child: SizedBox(height: 3, child: ColoredBox(color: PhotonColors.accent))),
                    ]),
                  ),
                ],
              ]);
            }),
          ],
          if (page.tip != null) ...[
            const SizedBox(height: Space.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.s2),
              decoration: BoxDecoration(
                color: PhotonColors.panel,
                border: Border.all(color: PhotonColors.line),
                borderRadius: BorderRadius.circular(PhotonRadius.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: PhotonColors.accent2, size: 18),
                  const SizedBox(width: Space.s1),
                  Expanded(child: Text(page.tip!, style: PText.small)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
