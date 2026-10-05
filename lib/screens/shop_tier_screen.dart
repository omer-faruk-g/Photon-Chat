import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
import '../vip.dart';

/// One tier in full: everything it carries, cumulatively, plus the price.
///
/// Buying is closed. Google Play Billing needs Play Console product ids, a
/// service-account key and a signed build to verify receipts server-side; until
/// those exist an "almost working" purchase path would be worse than an honest
/// closed door. Until then only the server (admin token) can grant a tier.
class ShopTierScreen extends StatelessWidget {
  final VipTier tier;
  final String fipId;
  final VipTier currentTier;

  const ShopTierScreen({
    super.key,
    required this.tier,
    required this.fipId,
    required this.currentTier,
  });

  /// Ödeme henüz bağlı değil. Katmanı yalnızca sunucu (yönetici) verebilir;
  /// uygulamada katman veren hiçbir yol yok.
  Future<void> _buy(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLang.instance.t('shopOutOfService')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Everything up to and including this tier — the ladder is cumulative.
    final included = VipTier.purchasable.where((t) => t.rank <= tier.rank).toList();
    final owned = currentTier.rank >= tier.rank;

    return Scaffold(
      appBar: AppBar(title: Text(tier.label)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${tier.priceTry}₺',
                style: TextStyle(
                    color: PhotonColors.accent,
                    fontSize: 34,
                    fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Text(AppLang.instance.t('shopPerMonth'),
                  style: PText.small),
            ),
            const Spacer(),
            if (owned)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ]),
          const SizedBox(height: 16),
          Text(AppLang.instance.t('shopAllFeatures'),
              style: TextStyle(
                  color: PhotonColors.textDim, fontSize: 11, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PhotonColors.panel,
              border: Border.all(color: PhotonColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: included
                  .map((t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(children: [
                          Icon(Icons.check_outlined, size: 15, color: PhotonColors.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(AppLang.instance.t(t.addsKey),
                                style: TextStyle(
                                    color: PhotonColors.text, fontSize: 13)),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
          if (tier.boldMessages) ...[
            const SizedBox(height: 8),
            Text(AppLang.instance.t('boldHint'),
                style: TextStyle(
                    color: PhotonColors.textDim, fontSize: 11, height: 1.5)),
          ],
          const SizedBox(height: 24),
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
