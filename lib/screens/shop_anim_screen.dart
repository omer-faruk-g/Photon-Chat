import 'package:flutter/material.dart';
import '../anims/profile_anim_player.dart';
import '../i18n.dart';
import '../photon_api.dart';
import '../profile_anim.dart';
import '../theme.dart';
import '../vip.dart';

/// One animation (or the five-pack) in full, with its price for this user.
///
/// Buying is closed for the same reason tiers are: Play Console product ids and
/// a service-account key are needed to verify receipts and neither exists. The
/// owner test code is the one way past it.
class ShopAnimScreen extends StatelessWidget {
  /// Null means the bundle — all five in one purchase.
  final ProfileAnim? anim;
  final String fipId;
  final VipTier tier;
  final AnimOwnership owned;
  final Color accent;

  /// TEMPORARY, mirrors ShopTierScreen. Remove with the redeem panel.
  final bool ownerMode;

  const ShopAnimScreen({
    super.key,
    required this.anim,
    required this.fipId,
    required this.tier,
    required this.owned,
    required this.accent,
    this.ownerMode = false,
  });

  bool get _isBundle => anim == null;

  bool get _alreadyOwned =>
      _isBundle ? owned.hasAll : owned.owns(anim!);

  /// Bundle is a flat price — the tier discount deliberately does not stack.
  String get _priceLabel => _isBundle
      ? '$kAnimBundleTry₺'
      : _formatTry(animPriceFor(tier));

  static String _formatTry(double v) {
    final whole = v == v.roundToDouble();
    return whole
        ? '${v.toStringAsFixed(0)}₺'
        : '${v.toStringAsFixed(2).replaceAll('.', ',')}₺';
  }

  Future<void> _buy(BuildContext context) async {
    if (!ownerMode) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLang.instance.t('shopOutOfService')),
      ));
      return;
    }
    final ids = _isBundle
        ? ProfileAnim.purchasable.map((a) => a.id).toList()
        : [anim!.id];
    final ok = await PhotonApi.grantAnims(fipId, ids);
    if (ok) VipCache.instance.invalidate(fipId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(AppLang.instance.t(ok ? 'animGranted' : 'animGrantFailed')),
    ));
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final discount = _isBundle ? 0 : animDiscountPercent(tier);
    final title = _isBundle
        ? AppLang.instance.t('animBundle')
        : AppLang.instance.t(anim!.nameKey);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProfileAnimPreview(
            anim: _isBundle ? ProfileAnim.purchasable.first : anim!,
            accent: accent,
            height: 200,
          ),
          const SizedBox(height: 18),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_priceLabel,
                style: TextStyle(
                    color: PhotonColors.accent,
                    fontSize: 30,
                    fontWeight: FontWeight.w700)),
            if (discount > 0) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '$kAnimPriceTry₺',
                  style: TextStyle(
                      color: PhotonColors.textDim,
                      fontSize: 14,
                      decoration: TextDecoration.lineThrough),
                ),
              ),
            ],
            const Spacer(),
            if (_alreadyOwned)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: PhotonColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                    AppLang.instance
                        .t(_isBundle ? 'animBundleOwned' : 'animOwned'),
                    style: TextStyle(
                        color: PhotonColors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          if (discount > 0) ...[
            const SizedBox(height: 6),
            Text('%$discount ${AppLang.instance.t('animDiscountNote')}',
                style:
                    TextStyle(color: PhotonColors.accent2, fontSize: 11)),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: PhotonColors.panel,
              border: Border.all(color: PhotonColors.line),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _isBundle
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: ProfileAnim.purchasable
                        .map((a) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 5),
                              child: Row(children: [
                                Icon(Icons.check,
                                    size: 15, color: PhotonColors.accent),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                      AppLang.instance.t(a.nameKey),
                                      style: TextStyle(
                                          color: PhotonColors.text,
                                          fontSize: 13)),
                                ),
                              ]),
                            ))
                        .toList(),
                  )
                : Text(AppLang.instance.t(anim!.descKey),
                    style: TextStyle(
                        color: PhotonColors.text, fontSize: 13, height: 1.5)),
          ),
          const SizedBox(height: 24),
          if (!_alreadyOwned)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: photonPrimaryButtonStyle(),
                onPressed: () => _buy(context),
                child: Text(AppLang.instance.t('shopBuy')),
              ),
            ),
        ],
      ),
    );
  }
}
