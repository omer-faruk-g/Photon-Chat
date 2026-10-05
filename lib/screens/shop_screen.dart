import 'package:flutter/material.dart';
import '../i18n.dart';
import '../photon_api.dart';
import '../theme.dart';
import '../profile_anim.dart';
import '../vip.dart';
import 'shop_anim_screen.dart';
import 'shop_tier_screen.dart';

/// Tier catalogue. Each row names only what that tier *adds* — showing the full
/// cumulative list eight times over would be unreadable. The complete list lives
/// on the detail page.
class ShopScreen extends StatefulWidget {
  final String fipId;
  const ShopScreen({super.key, required this.fipId});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  VipStatus _status = VipStatus.none;
  AnimOwnership _anims = AnimOwnership.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await PhotonApi.getTier(widget.fipId);
    final animRaw = await PhotonApi.getAnims(widget.fipId);
    if (!mounted) return;
    setState(() {
      _status = raw == null ? VipStatus.none : VipStatus.fromJson(raw);
      _anims =
          animRaw == null ? AnimOwnership.empty : AnimOwnership.fromJson(animRaw);
      _loading = false;
    });
  }

  Future<void> _pickColor(Color c) async {
    final ok = await PhotonApi.setTierPrefs(widget.fipId, color: c.value);
    if (ok) VipCache.instance.invalidate(widget.fipId);
    if (!mounted) return;
    if (ok) {
      setState(() => _status = VipStatus(
            tier: _status.tier,
            color: c,
            fakeName: _status.fakeName,
            fakeActive: _status.fakeActive,
            expiresAt: _status.expiresAt,
          ));
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance
          .t(ok ? 'shopColorSaved' : 'shopColorFailed')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final active = _status.effectiveTier;
    return Scaffold(
      appBar: AppBar(title: Text(AppLang.instance.t('shopTitle'))),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: PhotonColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.s2, Space.s3, Space.s2, Space.s5),
              children: [
                _currentTierCard(active),
                if (active.coloredName) ...[
                  const SizedBox(height: 16),
                  _colorPicker(),
                ],
                const SizedBox(height: 16),
                ...VipTier.purchasable.map((t) => _tierRow(t, active)),
                const SizedBox(height: 24),
                Text(trUpper(AppLang.instance.t('animSectionTitle')),
                    style: PText.label),
                const SizedBox(height: 8),
                ...ProfileAnim.purchasable.map((a) => _animRow(a, active)),
                _animRow(null, active),
                const SizedBox(height: 8),
                Text(AppLang.instance.t('animFreeNote'),
                    style: PText.meta),
              ],
            ),
    );
  }

  Widget _currentTierCard(VipTier active) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PhotonColors.accentWash,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(PhotonRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trUpper(AppLang.instance.t('shopCurrentTier')), style: PText.label),
          const SizedBox(height: Space.s1),
          Text(
            active == VipTier.none ? AppLang.instance.t('vipNone') : active.label,
            style: PText.h1.copyWith(color: _status.color ?? PhotonColors.text),
          ),
        ]),
      );

  Widget _colorPicker() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PhotonColors.panel,
          border: Border.all(color: PhotonColors.line),
          borderRadius: BorderRadius.circular(PhotonRadius.card),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trUpper(AppLang.instance.t('shopColorSection')),
              style: PText.label),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kVipColors.map((c) {
              final selected = _status.color?.value == c.value;
              return GestureDetector(
                onTap: () => _pickColor(c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? PhotonColors.text : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ]),
      );

  /// A single animation, or the five-pack when [anim] is null.
  Widget _animRow(ProfileAnim? anim, VipTier active) {
    final isBundle = anim == null;
    final owned = isBundle ? _anims.hasAll : _anims.owns(anim);
    final label = isBundle
        ? AppLang.instance.t('animBundle')
        : AppLang.instance.t(anim.nameKey);
    final desc = isBundle
        ? AppLang.instance.t('animBundleDesc')
        : AppLang.instance.t(anim.descKey);
    // The bundle is a flat price; the tier discount deliberately does not stack.
    final price = isBundle
        ? '$kAnimBundleTry₺'
        : _formatTry(animPriceFor(active));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverCard(
        padding: EdgeInsets.zero,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopAnimScreen(
                anim: anim,
                fipId: widget.fipId,
                tier: active,
                owned: _anims,
                accent: _status.color ?? PhotonColors.accent,
              ),
            ),
          );
          if (mounted) _load();
        },
        borderColor: owned ? PhotonColors.accent : null,
        color: owned ? PhotonColors.accentWash : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1 + 4),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(label,
                            style: PText.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (owned) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: PhotonColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              AppLang.instance.t(
                                  isBundle ? 'animBundleOwned' : 'animOwned'),
                              style: TextStyle(
                                  color: PhotonColors.accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(desc,
                        style: TextStyle(
                            color: PhotonColors.textDim, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ]),
            ),
            if (!owned)
              Text(price,
                  style: PText.title.merge(PText.tabular).copyWith(color: PhotonColors.accent)),
            Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 18),
          ]),
        ),
      ),
    );
  }

  /// 25% off 50₺ is 37,50₺ — the only discount that lands off a whole lira.
  static String _formatTry(double v) => v == v.roundToDouble()
      ? '${v.toStringAsFixed(0)}₺'
      : '${v.toStringAsFixed(2).replaceAll('.', ',')}₺';

  Widget _tierRow(VipTier tier, VipTier active) {
    final isActive = tier == active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: HoverCard(
        padding: EdgeInsets.zero,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ShopTierScreen(
                tier: tier,
                fipId: widget.fipId,
                currentTier: active,
              ),
            ),
          );
          if (mounted) _load();
        },
        borderColor: isActive ? PhotonColors.accent : null,
        color: isActive ? PhotonColors.accentWash : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s1 + 4),
          child: Row(children: [
            // Merdivendeki yeri: her katman bir öncekinin hepsini kapsar.
            Container(
              width: Space.s4, height: Space.s4, alignment: Alignment.center,
              margin: const EdgeInsets.only(right: Space.s2),
              decoration: BoxDecoration(
                color: isActive ? PhotonColors.accent : PhotonColors.bg,
                border: Border.all(color: isActive ? PhotonColors.accent : PhotonColors.line),
                borderRadius: BorderRadius.circular(PhotonRadius.pill),
              ),
              child: Text('${tier.rank}',
                  style: PText.small.merge(PText.tabular).copyWith(
                      color: isActive ? PhotonColors.onAccent : PhotonColors.textDim, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(tier.label,
                      style: PText.title),
                  if (isActive) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: PhotonColors.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(AppLang.instance.t('shopActive'),
                          style: TextStyle(
                              color: PhotonColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 2),
                Text('+ ${AppLang.instance.t(tier.addsKey)}',
                    style: PText.meta),
              ]),
            ),
            Text('${tier.priceTry}₺${AppLang.instance.t('shopPerMonth')}',
                style: PText.title.merge(PText.tabular).copyWith(color: PhotonColors.accent)),
            Icon(Icons.chevron_right_outlined, color: PhotonColors.textDim, size: 18),
          ]),
        ),
      ),
    );
  }
}
